#!/usr/bin/env bash
# =============================================================================
# diagnostic.sh — Outil de diagnostic et résolution de problèmes RTMP
# =============================================================================
# Usage : ./scripts/diagnostic.sh [OPTION]
#   --rtmp        Diagnostic RTMP (ports, nginx, bloc RTMP)
#   --ffmpeg      Test FFmpeg avec source BTFS vers RTMP local
#   --journaux    Afficher les derniers journaux de diffusion
#   --complet     Diagnostic complet (système, BTFS, RTMP, FFmpeg)
#   --aide        Afficher cette aide
# =============================================================================

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJET_DIR="$(dirname "${SCRIPT_DIR}")"
source "${PROJET_DIR}/conf/orbis.conf"

# --- Couleurs et symboles ---
VERT='\033[0;32m'
ROUGE='\033[0;31m'
ORANGE='\033[0;33m'
BLEU='\033[0;34m'
CYAN='\033[0;36m'
GRAS='\033[1m'
RAZ='\033[0m'

section() { echo -e "\n${GRAS}${CYAN}══ $1 ══${RAZ}"; }
ok()      { echo -e "  ${VERT}✓${RAZ} $1"; }
echec()   { echo -e "  ${ROUGE}✗${RAZ} $1"; }
info()    { echo -e "  ${BLEU}ℹ${RAZ} $1"; }
avert()   { echo -e "  ${ORANGE}⚠${RAZ} $1"; }

# =============================================================================
# DIAGNOSTIC RTMP (Le plus important pour votre probleme)
# =============================================================================
diag_rtmp() {
    section "Diagnostic RTMP"

    # 1. nginx est-il actif ?
    echo ""
    info "1. Vérification du service nginx..."
    if sudo systemctl is-active --quiet nginx 2>/dev/null; then
        ok "Service nginx ACTIF"
    else
        echec "Service nginx INACTIF"
        avert "Lancez : sudo systemctl start nginx"
        return 1
    fi

    # 2. nginx écoute-t-il sur le port 1935 ?
    echo ""
    info "2. Vérification du port RTMP (${NGINX_PORT_RTMP})..."
    if ss -tlnp 2>/dev/null | grep -q ":${NGINX_PORT_RTMP}\s"; then
        ok "Port ${NGINX_PORT_RTMP} en écoute"
        echo "    $(ss -tlnp 2>/dev/null | grep ":${NGINX_PORT_RTMP}")"
    else
        echec "Port ${NGINX_PORT_RTMP} FERME"
        avert "nginx n'écoute pas sur le port RTMP"
        return 1
    fi

    # 3. La syntax nginx est-elle valide ?
    echo ""
    info "3. Vérification de la syntax nginx..."
    if sudo nginx -t 2>&1 | grep -q "syntax is ok"; then
        ok "Syntax nginx valide"
    else
        echec "Erreur de syntax nginx :"
        sudo nginx -t 2>&1 | head -5
        return 1
    fi

    # 4. Le module RTMP est-il chargé ?
    echo ""
    info "4. Vérification du module RTMP..."
    if sudo nginx -T 2>&1 | grep -q "ngx_rtmp_module.so"; then
        ok "Module RTMP chargé"
    elif [[ -f /etc/nginx/modules-enabled/50-mod-rtmp.conf ]]; then
        ok "Module RTMP chargé via modules-enabled/"
    else
        echec "Module RTMP NON DETECTABLE"
        avert "Installez : sudo apt install libnginx-mod-rtmp"
        avert "Puis redémarrez : sudo systemctl restart nginx"
        return 1
    fi

    # 5. Le bloc RTMP est-il présent et généré ?
    echo ""
    info "5. Vérification du bloc RTMP généré..."
    if [[ -f /etc/nginx/orbis-rtmp-block.conf ]]; then
        ok "Fichier /etc/nginx/orbis-rtmp-block.conf présent"
        echo ""
        echo "    Contenu du bloc RTMP :"
        echo "    ─────────────────────────"
        sudo cat /etc/nginx/orbis-rtmp-block.conf | sed 's/^/    /'
        echo "    ─────────────────────────"
    else
        echec "Bloc RTMP NON GENERE"
        avert "Lancez d'abord : ./scripts/diffuser.sh -l ldl/ldl_tot.txt -p dlive -n"
        return 1
    fi

    # 6. Le bloc RTMP est-il inclus dans nginx.conf ?
    echo ""
    info "6. Vérification de l'inclusion du bloc RTMP..."
    if sudo grep -q "orbis-rtmp-block.conf" /etc/nginx/nginx.conf 2>/dev/null; then
        ok "Inclusion du bloc RTMP présente dans nginx.conf"
    else
        echec "Bloc RTMP NON INCLUS dans nginx.conf"
        avert "Le script diffuser.sh doit ajouter cette inclusion automatiquement"
        return 1
    fi

    # 7. Test de connexion TCP basique au port 1935
    echo ""
    info "7. Test de connexion TCP sur 127.0.0.1:${NGINX_PORT_RTMP}..."
    if timeout 3 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/${NGINX_PORT_RTMP}" 2>/dev/null; then
        ok "Connexion TCP possible sur le port ${NGINX_PORT_RTMP}"
    else
        echec "Impossible de se connecter au port ${NGINX_PORT_RTMP}"
        avert "Le serveur RTMP n'accepte pas les connexions"
        return 1
    fi

    # 8. Vérifier les logs d'erreur nginx
    echo ""
    info "8. Vérification des erreurs nginx récentes..."
    local errors
    errors=$(sudo tail -20 /var/log/nginx/error.log 2>/dev/null | grep -i "error\|critical" || echo "")
    if [[ -z "${errors}" ]]; then
        ok "Aucune erreur critique dans les logs nginx"
    else
        avert "Erreurs détectées :"
        echo "${errors}" | sed 's/^/    /'
    fi

    echo ""
    ok "Diagnostic RTMP terminé"
    return 0
}

# =============================================================================
# TEST FFMPEG → RTMP (Reproduire l'erreur exacte)
# =============================================================================
test_ffmpeg_rtmp() {
    section "Test FFmpeg → RTMP local"

    info "Ce test va envoyer un flux vidéo test vers nginx-rtmp"
    info "Durée : ~10 secondes"
    echo ""

    local log_test="/tmp/ffmpeg_rtmp_test_$(date +%s).log"

    # Créer une vidéo de test (couleur noire)
    info "Génération de la source vidéo test (5 secondes de couleur noire)..."
    "${FFMPEG}" \
        -hide_banner -loglevel warning \
        -f lavfi -i "color=c=black:s=640x480:d=5" \
        -f lavfi -i "anullsrc=r=44100:cl=mono" \
        -c:v libx264 -preset ultrafast -b:v 500k \
        -c:a aac -b:a 64k \
        -f flv "rtmp://127.0.0.1:${NGINX_PORT_RTMP}/diffusion/test_orbis" \
        2>&1 | tee "${log_test}" &

    local pid_ffmpeg=$!
    sleep 8
    kill -TERM "${pid_ffmpeg}" 2>/dev/null || true
    wait "${pid_ffmpeg}" 2>/dev/null || true

    echo ""
    echo "    Logs FFmpeg du test :"
    echo "    ───────────────────────────────"
    cat "${log_test}" | sed 's/^/    /'
    echo "    ───────────────────────────────"
    echo ""

    # Analyser les résultats
    if grep -q "muxing overhead" "${log_test}" 2>/dev/null; then
        ok "✓ Push RTMP REUSSI (flux envoyé vers nginx)"
        info "Le problème n'est PAS dans la configuration RTMP."
        info "Vérifiez les clés de flux DLive/Kick dans orbis.conf"
    elif grep -q "Input/output error" "${log_test}" 2>/dev/null; then
        echec "✗ ERREUR DE CONNEXION RTMP (Input/output error)"
        echo ""
        echo "    DIAGNOSTIC :"
        echo "    ────────────"
        echo "    Le bloc RTMP refuse les connexions entrantes."
        echo "    Causes possibles :"
        echo "      1. Les directives 'allow publish' / 'deny publish' bloquent 127.0.0.1"
        echo "      2. Le bloc RTMP a une erreur de syntax"
        echo "      3. nginx-rtmp module version obsolète ou bugué"
        echo ""
        echo "    Actions à prendre :"
        echo "      → Vérifier /etc/nginx/orbis-rtmp-block.conf (voir ci-dessus)"
        echo "      → Relancer : sudo systemctl restart nginx"
        echo "      → Relancer le test : ./scripts/diagnostic.sh --ffmpeg"
    else
        avert "Résultat ambigu du test FFmpeg"
        info "Consultez les logs ci-dessus pour plus de détails"
    fi

    rm -f "${log_test}"
}

# =============================================================================
# DIAGNOSTIC SYSTÈME (Basique)
# =============================================================================
diag_systeme() {
    section "Système"
    echo "  Date         : $(date)"
    echo "  Hostname     : $(hostname)"
    echo "  Architecture : $(uname -m)"
    echo "  Noyau        : $(uname -r)"
    echo "  Charge CPU   : $(uptime | sed 's/.*load average: //')"
    echo "  RAM libre    : $(awk '/MemAvailable/{printf "%.0f Mo", $2/1024}' /proc/meminfo)"
}

# =============================================================================
# DIAGNOSTIC BTFS
# =============================================================================
diag_btfs() {
    section "BTFS"

    info "Nœud : ${BTFS_REPO}"
    info "Chaîne : ${BTFS_CHAINE_ID} ($([ "${BTFS_CHAINE_ID}" = "1029" ] && echo "testnet" || echo "mainnet"))"
    echo ""

    # Daemon BTFS actif ?
    info "Vérification du démon BTFS..."
    if pgrep -x "btfs" &>/dev/null; then
        ok "Démon BTFS actif"
    else
        echec "Démon BTFS inactif"
        info "Lancez manuellement : btfs daemon --chain-id ${BTFS_CHAINE_ID}"
        return 1
    fi

    # Passerelle HTTP accessible ?
    echo ""
    info "Vérification de la passerelle HTTP (port ${BTFS_PORT_PASSERELLE})..."
    if "${CURL}" -sf --max-time 5 --range "0-511" "${BTFS_PASSERELLE}/${BTFS_HASH_TEST}" &>/dev/null; then
        ok "Passerelle HTTP accessible"
    else
        echec "Passerelle HTTP inaccessible"
        avert "Vérifiez que le démon BTFS écoute bien sur le port ${BTFS_PORT_PASSERELLE}"
        return 1
    fi

    # Test des URLs BTFS réelles
    echo ""
    info "Test des sources BTFS réelles :"
    local -a urls_test=(
        "http://127.0.0.1:8080/btfs/QmbQb1kfwEmf4sqCUcccDYHBiuvKAsE4h8LQsQJ13VvZR2"
        "http://127.0.0.1:8080/btfs/QmW7shMNQYCgnvNWntGTZ7cyfr3KD4uPFigXz1wWceCHd5"
    )
    for url in "${urls_test[@]}"; do
        local hash
        hash="$(basename "${url}")"
        printf "    %s : " "${hash:0:20}..."
        local code_http
        code_http=$("${CURL}" -sf -o /dev/null --max-time 20 -w "%{http_code}" "${url}" 2>/dev/null || echo "000")
        if [[ "${code_http}" =~ ^2 ]]; then
            echo -e "${VERT}HTTP ${code_http} ✓${RAZ}"
        else
            echo -e "${ROUGE}HTTP ${code_http} ✗${RAZ}"
        fi
    done
}

# =============================================================================
# JOURNAUX DIFFUSION
# =============================================================================
cmd_journaux() {
    section "Derniers journaux de diffusion"
    local dernier
    dernier=$(ls -t "${REPERTOIRE_JOURNAUX}"/diffusion_*.log 2>/dev/null | head -1 || echo "")
    if [[ -z "${dernier}" ]]; then
        avert "Aucun journal trouvé dans ${REPERTOIRE_JOURNAUX}"
        return
    fi
    info "Fichier : ${dernier}"
    echo ""
    tail -50 "${dernier}"
}

# =============================================================================
# POINT D'ENTREE
# =============================================================================
case "${1:---rtmp}" in
    --rtmp|-r)
        diag_rtmp
        ;;
    --ffmpeg|-f)
        if ! diag_rtmp > /dev/null 2>&1; then
            echo ""
            echec "Le diagnostic RTMP a détecté des problèmes"
            echo "Corrigez-les d'abord avant de tester FFmpeg."
            exit 1
        fi
        test_ffmpeg_rtmp
        ;;
    --journaux|-j)
        cmd_journaux
        ;;
    --complet|-c)
        diag_systeme
        diag_btfs
        diag_rtmp
        echo ""
        info "Exécution du test FFmpeg..."
        test_ffmpeg_rtmp
        ;;
    --aide|-h|help)
        grep '^#' "${BASH_SOURCE[0]}" | grep -A10 'Usage' | sed 's/^# \?//'
        ;;
    *)
        echo "Option inconnue : $1"
        echo "Utiliser : ./scripts/diagnostic.sh --aide"
        exit 1
        ;;
esac
