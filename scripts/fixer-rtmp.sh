#!/usr/bin/env bash
# =============================================================================
# fixer-rtmp.sh -- Correction automatique des problemes RTMP
# =============================================================================
# Ce script corrige les problemes courants qui empechent RTMP de fonctionner :
#   1. nginx-rtmp module non installe
#   2. Bloc RTMP non genere ou mal inclus
#   3. nginx pas recharge apres changements
#   4. Directives allow/deny mal configurees
#   5. Port RTMP verrouille ou conflit
# =============================================================================

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJET_DIR="$(dirname "${SCRIPT_DIR}")"
FICHIER_CONF="${PROJET_DIR}/conf/orbis.conf"

if [[ ! -f "${FICHIER_CONF}" ]]; then
    echo "[ERREUR] Configuration introuvable : ${FICHIER_CONF}" >&2
    exit 1
fi

# shellcheck source=../conf/orbis.conf
source "${FICHIER_CONF}"

# --- Couleurs et symboles ---
VERT='\033[0;32m'
ROUGE='\033[0;31m'
ORANGE='\033[0;33m'
BLEU='\033[0;34m'
RAZ='\033[0m'

_echo() {
    local couleur="$1"; shift
    local symbole="$1"; shift
    local message="$*"
    printf "%s%s%s %s\n" "${couleur}" "${symbole}" "${RAZ}" "${message}"
}

echo_ok()    { _echo "${VERT}" "✓" "$@"; }
echo_err()   { _echo "${ROUGE}" "✗" "$@"; }
echo_warn()  { _echo "${ORANGE}" "⚠" "$@"; }
echo_info()  { _echo "${BLEU}" "ℹ" "$@"; }

# --- Utilites ---
require_sudo() {
    if ! sudo -n true 2>/dev/null; then
        echo_err "Ce script necesssite les privileges sudo"
        echo "Lancez avec : sudo ./scripts/fixer-rtmp.sh"
        exit 1
    fi
}

# =============================================================================
# CORRECTION 1 : Installer le module RTMP
# =============================================================================
fixer_module_rtmp() {
    echo ""
    echo_info "CORRECTION 1 : Installation du module nginx-rtmp"
    echo "─────────────────────────────────────────────────────"

    if sudo nginx -T 2>&1 | grep -q "ngx_rtmp_module.so" 2>/dev/null || \
       [[ -f /etc/nginx/modules-enabled/50-mod-rtmp.conf ]]; then
        echo_ok "Module RTMP deja installe"
        return 0
    fi

    echo_warn "Module RTMP non detecte. Installation en cours..."
    if sudo apt update && sudo apt install -y libnginx-mod-rtmp; then
        echo_ok "Module RTMP installe avec succes"
        return 0
    else
        echo_err "Echec de l'installation du module RTMP"
        echo "  Commande manuelle : sudo apt install libnginx-mod-rtmp"
        return 1
    fi
}

# =============================================================================
# CORRECTION 2 : Generer le bloc RTMP
# =============================================================================
fixer_bloc_rtmp() {
    echo ""
    echo_info "CORRECTION 2 : Generation du bloc RTMP"
    echo "─────────────────────────────────────────────────────"

    local rtmp_bloc="/etc/nginx/orbis-rtmp-block.conf"

    if [[ -f "${rtmp_bloc}" ]]; then
        echo_ok "Bloc RTMP deja genere : ${rtmp_bloc}"
        echo ""
        echo "  Contenu actuel :"
        sudo cat "${rtmp_bloc}" | sed 's/^/    /'
        echo ""
        read -p "  Regener le bloc ? (y/n) " -n 1 -r repondre
        echo ""
        [[ "${repondre}" != "y" ]] && return 0
    fi

    echo_warn "Generation du nouveau bloc RTMP..."

    # Generer le bloc (meme logique que dans diffuser.sh)
    {
        echo "# Genere par fixer-rtmp.sh le $(date +'%Y-%m-%d %H:%M:%S')"
        echo "rtmp {"
        echo "    server {"
        echo "        listen ${NGINX_PORT_RTMP};"
        echo "        chunk_size 4096;"
        echo "        max_message 1M;"
        echo ""
        echo "        application ${NGINX_CHEMIN_APPLICATION} {"
        echo "            live on;"
        echo "            record off;"
        echo "            allow publish 127.0.0.1;"
        echo "            deny publish all;"
        echo "            allow play all;"
        if [[ "${DLIVE_ACTIF}" == "true" ]] && [[ -n "${DLIVE_CLE_FLUX}" ]]; then
            echo "            push ${DLIVE_SERVEUR}/${DLIVE_CLE_FLUX};"
        fi
        if [[ "${KICK_ACTIF}" == "true" ]] && [[ -n "${KICK_CLE_FLUX}" ]]; then
            echo "            push rtmp://127.0.0.1:${STUNNEL_PORT_LOCAL}/app/${KICK_CLE_FLUX};"
        fi
        echo "        }"
        echo "    }"
        echo "}"
    } | sudo tee "${rtmp_bloc}" > /dev/null

    echo_ok "Bloc RTMP genere : ${rtmp_bloc}"
    return 0
}

# =============================================================================
# CORRECTION 3 : Inclure le bloc dans nginx.conf
# =============================================================================
fixer_inclusion_rtmp() {
    echo ""
    echo_info "CORRECTION 3 : Inclusion du bloc RTMP dans nginx.conf"
    echo "─────────────────────────────────────────────────────"

    local nginx_conf="/etc/nginx/nginx.conf"
    local rtmp_bloc="/etc/nginx/orbis-rtmp-block.conf"

    if sudo grep -q "orbis-rtmp-block.conf" "${nginx_conf}" 2>/dev/null; then
        echo_ok "Inclusion deja presente dans ${nginx_conf}"
        return 0
    fi

    echo_warn "Ajout de l'inclusion du bloc RTMP..."
    echo "" | sudo tee -a "${nginx_conf}" > /dev/null
    echo "# Orbis Alternis -- bloc RTMP" | sudo tee -a "${nginx_conf}" > /dev/null
    echo "include ${rtmp_bloc};" | sudo tee -a "${nginx_conf}" > /dev/null

    echo_ok "Inclusion du bloc RTMP ajoutee"
    return 0
}

# =============================================================================
# CORRECTION 4 : Valider la syntax nginx
# =============================================================================
fixer_validation_nginx() {
    echo ""
    echo_info "CORRECTION 4 : Validation de la syntaxe nginx"
    echo "─────────────────────────────────────────────────────"

    if ! sudo nginx -t 2>&1 | tee /tmp/nginx_test.log | grep -q "syntax is ok"; then
        echo_err "Erreur de syntaxe nginx detectee :"
        sudo nginx -t 2>&1 | head -10
        echo ""
        echo_warn "Diagnostique complet :"
        sudo nginx -T 2>&1 | head -50
        return 1
    fi

    echo_ok "Syntaxe nginx valide"
    return 0
}

# =============================================================================
# CORRECTION 5 : Recharger nginx
# =============================================================================
fixer_rechargement_nginx() {
    echo ""
    echo_info "CORRECTION 5 : Rechargement de nginx"
    echo "─────────────────────────────────────────────────────"

    if ! sudo systemctl is-active --quiet nginx 2>/dev/null; then
        echo_warn "nginx n'est pas actif. Demarrage..."
        sudo systemctl start nginx
    fi

    echo_warn "Rechargement de nginx..."
    if sudo systemctl reload nginx; then
        echo_ok "nginx recharge avec succes"
        sleep 2
        return 0
    else
        echo_err "Echec du rechargement de nginx"
        echo "  Diagnostic : sudo systemctl status nginx"
        return 1
    fi
}

# =============================================================================
# CORRECTION 6 : Verifier les permissions et ports
# =============================================================================
fixer_permissions_ports() {
    echo ""
    echo_info "CORRECTION 6 : Verification des permissions et ports"
    echo "─────────────────────────────────────────────────────"

    # Verifier que le port 1935 n'est pas utilise par autre chose
    if lsof -i :1935 2>/dev/null | grep -qv nginx; then
        echo_warn "Port 1935 utilise par autre chose que nginx :"
        sudo lsof -i :1935 2>/dev/null || true
        echo "  Arretez les autres services ou modifiez NGINX_PORT_RTMP"
        return 1
    fi

    # Verifier les permissions nginx sur le repertoire journal
    if [[ -d "${REPERTOIRE_JOURNAUX}" ]]; then
        if ! sudo test -w "${REPERTOIRE_JOURNAUX}"; then
            echo_warn "nginx ne peut pas ecrire dans ${REPERTOIRE_JOURNAUX}"
            echo "  Correction : sudo chown -R www-data:www-data ${REPERTOIRE_JOURNAUX}"
            sudo chown -R www-data:www-data "${REPERTOIRE_JOURNAUX}" 2>/dev/null || true
        fi
    fi

    echo_ok "Permissions et ports verifies"
    return 0
}

# =============================================================================
# CORRECTION 7 : Nettoyer les anciennes configurations
# =============================================================================
fixer_nettoyage() {
    echo ""
    echo_info "CORRECTION 7 : Nettoyage des anciennes configurations"
    echo "─────────────────────────────────────────────────────"

    local fichiers_a_supprimer=(
        "/etc/nginx/sites-enabled/orbis-rtmp.conf"
        "/etc/nginx/sites-enabled/orbis-rtmp"
        "/etc/nginx/conf.d/orbis-rtmp.conf"
    )

    local nb_supprimes=0
    for f in "${fichiers_a_supprimer[@]}"; do
        if [[ -f "${f}" ]]; then
            echo_warn "Suppression du fichier obsolete : ${f}"
            sudo rm -f "${f}"
            ((nb_supprimes++))
        fi
    done

    if (( nb_supprimes > 0 )); then
        echo_ok "${nb_supprimes} fichier(s) obsolete(s) supprime(s)"
    else
        echo_ok "Aucun fichier obsolete a nettoyer"
    fi

    return 0
}

# =============================================================================
# TESTE FINAL
# =============================================================================
test_final() {
    echo ""
    echo_info "TEST FINAL : Verification que RTMP fonctionne"
    echo "─────────────────────────────────────────────────────"

    # 1. nginx ecoute-t-il sur le port 1935 ?
    if ! ss -tlnp 2>/dev/null | grep -q ":${NGINX_PORT_RTMP}\s"; then
        echo_err "nginx n'ecoute pas sur le port ${NGINX_PORT_RTMP}"
        return 1
    fi
    echo_ok "nginx ecoute sur le port ${NGINX_PORT_RTMP}"

    # 2. Connexion TCP possible ?
    if ! timeout 2 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/${NGINX_PORT_RTMP}" 2>/dev/null; then
        echo_err "Impossible de se connecter au port RTMP"
        return 1
    fi
    echo_ok "Connexion TCP possible sur le port RTMP"

    # 3. Module RTMP charge ?
    if ! sudo nginx -T 2>&1 | grep -q "ngx_rtmp_module.so"; then
        echo_err "Module RTMP non detectable apres rechargement"
        return 1
    fi
    echo_ok "Module RTMP charge et operationnel"

    echo ""
    echo_ok "RTMP semble operationnel !"
    echo ""
    echo "Prochaine etape : lancer la diffusion"
    echo "  $ ./scripts/diffuser.sh -l ldl/ldl_tot.txt -p dlive -n"
    echo ""

    return 0
}

# =============================================================================
# POINT D'ENTREE PRINCIPAL
# =============================================================================
main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║   Fixer RTMP - Correction automatique Orbis Alternis  ║"
    echo "╚════════════════════════════════════════════════════════╝"

    require_sudo

    # Executer les corrections dans l'ordre
    local etape=0
    local nb_erreurs=0

    for correction in \
        fixer_nettoyage \
        fixer_module_rtmp \
        fixer_bloc_rtmp \
        fixer_inclusion_rtmp \
        fixer_validation_nginx \
        fixer_rechargement_nginx \
        fixer_permissions_ports \
        test_final; do

        ((etape++))
        if ! "${correction}"; then
            ((nb_erreurs++))
        fi
    done

    echo ""
    echo "╔════════════════════════════════════════════════════════╗"
    if (( nb_erreurs == 0 )); then
        echo "║   ✓ Toutes les corrections ont ete appliquees       ║"
    else
        echo "║   ⚠ ${nb_erreurs} erreur(s) detectee(s) - voir ci-dessus      ║"
    fi
    echo "╚════════════════════════════════════════════════════════╝"
    echo ""

    return $(( nb_erreurs > 0 ? 1 : 0 ))
}

main "$@"
