#!/usr/bin/env bash
# =============================================================================
# git-publier.sh -- Publication automatique sur GitHub avec securite
# =============================================================================
# Ce script :
#   1. Verifie que git est configure
#   2. Nettoie les cles de flux (DLIVE/KICK) dans orbis.conf avant commit
#   3. Corrige les BOM UTF-8 et fins de ligne CRLF -> LF sur tous les fichiers
#   4. Rend les scripts .sh executables (chmod +x)
#   5. Effectue le commit avec un message automatique ou personnalise
#   6. Pousse sur GitHub
#   7. Restaure les cles de flux apres le push (fichier local intact)
#
# Usage : ./scripts/git-publier.sh ["message de commit optionnel"]
#
# SECURITE : Les cles DLIVE_CLE_FLUX et KICK_CLE_FLUX ne quittent JAMAIS
#            ce Raspberry Pi. Elles sont masquees avant le commit et
#            restaurees automatiquement apres le push.
# =============================================================================

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJET_DIR="$(dirname "${SCRIPT_DIR}")"
FICHIER_CONF="${PROJET_DIR}/conf/orbis.conf"

# --- Couleurs ----------------------------------------------------------------
VERT='\033[0;32m'
ROUGE='\033[0;31m'
ORANGE='\033[0;33m'
BLEU='\033[0;34m'
CYAN='\033[0;36m'
GRAS='\033[1m'
RAZ='\033[0m'

ok()     { echo -e "  ${VERT}✓${RAZ} $*"; }
erreur() { echo -e "  ${ROUGE}✗${RAZ} $*" >&2; }
avert()  { echo -e "  ${ORANGE}⚠${RAZ} $*"; }
info()   { echo -e "  ${BLEU}ℹ${RAZ} $*"; }
titre()  { echo -e "\n${GRAS}${CYAN}▶ $*${RAZ}"; }

# --- Variables ---------------------------------------------------------------
MSG_COMMIT="${1:-}"
CLES_SAUVEGARDEES=false
DLIVE_CLE_SAUVEGARDE=""
KICK_CLE_SAUVEGARDE=""

# =============================================================================
# NETTOYAGE EN CAS D'INTERRUPTION : restaurer les cles avant de quitter
# =============================================================================
restaurer_cles() {
    if [[ "${CLES_SAUVEGARDEES}" == "true" ]]; then
        avert "Restauration des cles de flux (suite a interruption)..."
        if [[ -n "${DLIVE_CLE_SAUVEGARDE}" ]]; then
            sed -i "s|DLIVE_CLE_FLUX=.*|DLIVE_CLE_FLUX=\"${DLIVE_CLE_SAUVEGARDE}\"|" \
                "${FICHIER_CONF}"
        fi
        if [[ -n "${KICK_CLE_SAUVEGARDE}" ]]; then
            sed -i "s|KICK_CLE_FLUX=.*|KICK_CLE_FLUX=\"${KICK_CLE_SAUVEGARDE}\"|" \
                "${FICHIER_CONF}"
        fi
        ok "Cles restaurees dans ${FICHIER_CONF}"
    fi
}
trap restaurer_cles EXIT INT TERM

# =============================================================================
# ETAPE 0 : Verifications prealables
# =============================================================================
titre "Etape 0 : Verifications prealables"

# Git installe ?
if ! command -v git &>/dev/null; then
    erreur "git n'est pas installe."
    erreur "  Installez-le : sudo apt install git"
    exit 1
fi
ok "git disponible ($(git --version | cut -d' ' -f3))"

# Sommes-nous dans le bon repertoire ?
if [[ ! -d "${PROJET_DIR}/.git" ]]; then
    erreur "Ce repertoire n'est pas un depot git : ${PROJET_DIR}"
    erreur "  Initialisez-le : git init && git remote add origin <url>"
    exit 1
fi
ok "Depot git detecte : ${PROJET_DIR}"

# Configuration git minimale
if ! git -C "${PROJET_DIR}" config user.email &>/dev/null || \
   [[ -z "$(git -C "${PROJET_DIR}" config user.email 2>/dev/null)" ]]; then
    avert "Email git non configure. Ajout d'une valeur par defaut..."
    git -C "${PROJET_DIR}" config user.email "orbis@alternis.local"
    git -C "${PROJET_DIR}" config user.name "Orbis Alternis"
fi
ok "Configuration git : $(git -C "${PROJET_DIR}" config user.name) <$(git -C "${PROJET_DIR}" config user.email)>"

# Remote configure ?
if ! git -C "${PROJET_DIR}" remote get-url origin &>/dev/null; then
    erreur "Aucun remote 'origin' configure."
    erreur "  Ajoutez-le : git remote add origin https://github.com/Thalyn-/diffuseur-rtmps-btfs-ARM64.git"
    exit 1
fi
ok "Remote origin : $(git -C "${PROJET_DIR}" remote get-url origin)"

# Fichier de config present ?
if [[ ! -f "${FICHIER_CONF}" ]]; then
    erreur "Fichier de configuration introuvable : ${FICHIER_CONF}"
    exit 1
fi
ok "Configuration : ${FICHIER_CONF}"

# =============================================================================
# ETAPE 1 : Sauvegarder et masquer les cles de flux (securite)
# =============================================================================
titre "Etape 1 : Securisation des cles de flux"

# Lire les cles actuelles
DLIVE_CLE_SAUVEGARDE="$(grep -oP '(?<=DLIVE_CLE_FLUX=")[^"]*' "${FICHIER_CONF}" 2>/dev/null || echo '')"
KICK_CLE_SAUVEGARDE="$(grep -oP '(?<=KICK_CLE_FLUX=")[^"]*' "${FICHIER_CONF}" 2>/dev/null || echo '')"
CLES_SAUVEGARDEES=true

# Masquer les cles dans le fichier (pour le commit)
sed -i 's|DLIVE_CLE_FLUX=.*|DLIVE_CLE_FLUX=""|' "${FICHIER_CONF}"
sed -i 's|KICK_CLE_FLUX=.*|KICK_CLE_FLUX=""|' "${FICHIER_CONF}"

if [[ -n "${DLIVE_CLE_SAUVEGARDE}" ]]; then
    ok "Cle DLive masquee pour le commit (sera restauree apres push)"
else
    info "Cle DLive deja vide (rien a masquer)"
fi
if [[ -n "${KICK_CLE_SAUVEGARDE}" ]]; then
    ok "Cle Kick masquee pour le commit (sera restauree apres push)"
else
    info "Cle Kick deja vide (rien a masquer)"
fi

# =============================================================================
# ETAPE 2 : Corriger BOM UTF-8 et fins de ligne CRLF -> LF
# =============================================================================
titre "Etape 2 : Correction BOM UTF-8 et fins de ligne (CRLF -> LF)"

# Liste des fichiers a nettoyer
mapfile -t FICHIERS_A_NETTOYER < <(find "${PROJET_DIR}" \
    -not -path '*/.git/*' \
    -not -path '*/journaux/*' \
    -not -name '*.png' \
    -not -name '*.jpg' \
    -not -name '*.jpeg' \
    -not -name '*.gif' \
    -not -name '*.ico' \
    -not -name '*.bin' \
    -type f \
    2>/dev/null)

nb_nettoyes=0
for fichier in "${FICHIERS_A_NETTOYER[@]}"; do
    # Verifier si le fichier a des CRLF ou BOM
    local_bom=false
    local_crlf=false

    # Detecter BOM UTF-8 (EF BB BF en debut de fichier)
    if head -c 3 "${fichier}" 2>/dev/null | grep -qP '^\xEF\xBB\xBF'; then
        local_bom=true
    fi

    # Detecter CRLF
    if file "${fichier}" 2>/dev/null | grep -qi "CRLF\|CR/LF"; then
        local_crlf=true
    elif cat "${fichier}" 2>/dev/null | grep -qP '\r'; then
        local_crlf=true
    fi

    if [[ "${local_bom}" == "true" ]] || [[ "${local_crlf}" == "true" ]]; then
        # Supprimer BOM
        sed -i '1s/^\xEF\xBB\xBF//' "${fichier}" 2>/dev/null || true
        # Convertir CRLF -> LF
        sed -i 's/\r$//' "${fichier}" 2>/dev/null || true
        info "Nettoye : $(basename "${fichier}")$(${local_bom} && echo ' [BOM]' || true)$(${local_crlf} && echo ' [CRLF]' || true)"
        nb_nettoyes=$((nb_nettoyes + 1))
    fi
done

if (( nb_nettoyes > 0 )); then
    ok "${nb_nettoyes} fichier(s) nettoye(s) (BOM/CRLF)"
else
    ok "Aucun fichier a nettoyer (pas de BOM ni CRLF)"
fi

# =============================================================================
# ETAPE 3 : Rendre les scripts shell executables
# =============================================================================
titre "Etape 3 : Permissions des scripts shell"

nb_chmod=0
while IFS= read -r -d '' script; do
    if [[ ! -x "${script}" ]]; then
        chmod +x "${script}"
        info "chmod +x : $(basename "${script}")"
        nb_chmod=$((nb_chmod + 1))
    fi
done < <(find "${PROJET_DIR}/scripts" -name "*.sh" -type f -print0 2>/dev/null)

if (( nb_chmod > 0 )); then
    ok "${nb_chmod} script(s) rendu(s) executables"
else
    ok "Tous les scripts sont deja executables"
fi

# =============================================================================
# ETAPE 4 : Verifier l'etat git et ajouter les fichiers modifies
# =============================================================================
titre "Etape 4 : Preparation du commit git"

cd "${PROJET_DIR}"

# Afficher les fichiers modifies
echo ""
info "Fichiers modifies (git status) :"
git status --short | sed 's/^/    /'

# Verifier s'il y a quelque chose a commiter
if git diff --quiet && git diff --cached --quiet && \
   [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
    ok "Aucun changement a commiter."
    # Restaurer les cles quand meme
    if [[ -n "${DLIVE_CLE_SAUVEGARDE}" ]]; then
        sed -i "s|DLIVE_CLE_FLUX=.*|DLIVE_CLE_FLUX=\"${DLIVE_CLE_SAUVEGARDE}\"|" \
            "${FICHIER_CONF}"
    fi
    if [[ -n "${KICK_CLE_SAUVEGARDE}" ]]; then
        sed -i "s|KICK_CLE_FLUX=.*|KICK_CLE_FLUX=\"${KICK_CLE_SAUVEGARDE}\"|" \
            "${FICHIER_CONF}"
    fi
    CLES_SAUVEGARDEES=false
    echo ""
    ok "Depot deja a jour. Rien a pousser."
    exit 0
fi

# Ajouter tous les fichiers modifies (hors .gitignore)
git add --all

echo ""
info "Fichiers qui seront commites :"
git diff --cached --name-status | sed 's/^/    /'

# =============================================================================
# ETAPE 5 : Construire le message de commit
# =============================================================================
titre "Etape 5 : Message de commit"

if [[ -z "${MSG_COMMIT}" ]]; then
    # Message automatique base sur les fichiers modifies
    NB_MODIFIES=$(git diff --cached --name-only | wc -l)
    LISTE_FICHIERS=$(git diff --cached --name-only | head -5 | tr '\n' ', ' | sed 's/,$//')
    if (( NB_MODIFIES > 5 )); then
        LISTE_FICHIERS="${LISTE_FICHIERS}... (+$((NB_MODIFIES - 5)) autres)"
    fi
    HORODATAGE="$(date +'%Y-%m-%d %H:%M')"
    MSG_COMMIT="chore: mise a jour automatique ${HORODATAGE}

Fichiers modifies : ${LISTE_FICHIERS}

- Correction BOM UTF-8 et fins de ligne CRLF -> LF
- Scripts .sh rendus executables
- Cles de flux masquees (securite)

[Publie par git-publier.sh depuis Raspberry Pi]"
fi

info "Message de commit :"
echo "${MSG_COMMIT}" | sed 's/^/    /'

# =============================================================================
# ETAPE 6 : Commit
# =============================================================================
titre "Etape 6 : Commit"

git commit -m "${MSG_COMMIT}"
ok "Commit effectue : $(git rev-parse --short HEAD)"

# =============================================================================
# ETAPE 7 : Pousser sur GitHub
# =============================================================================
titre "Etape 7 : Push sur GitHub"

# Detecter la branche courante
BRANCHE="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'main')"
info "Branche : ${BRANCHE}"
info "Remote  : $(git remote get-url origin)"

if git push origin "${BRANCHE}"; then
    ok "Push reussi sur GitHub (branche ${BRANCHE})"
else
    erreur "Echec du push sur GitHub"
    erreur "Verifiez votre connexion et vos credentials git"
    erreur "  Essayez manuellement : git push origin ${BRANCHE}"
    # Les cles seront restaurees par le trap EXIT
    exit 1
fi

# =============================================================================
# ETAPE 8 : Restaurer les cles de flux (apres push reussi)
# =============================================================================
titre "Etape 8 : Restauration des cles de flux"

if [[ -n "${DLIVE_CLE_SAUVEGARDE}" ]]; then
    sed -i "s|DLIVE_CLE_FLUX=.*|DLIVE_CLE_FLUX=\"${DLIVE_CLE_SAUVEGARDE}\"|" \
        "${FICHIER_CONF}"
    ok "Cle DLive restauree dans ${FICHIER_CONF}"
fi
if [[ -n "${KICK_CLE_SAUVEGARDE}" ]]; then
    sed -i "s|KICK_CLE_FLUX=.*|KICK_CLE_FLUX=\"${KICK_CLE_SAUVEGARDE}\"|" \
        "${FICHIER_CONF}"
    ok "Cle Kick restauree dans ${FICHIER_CONF}"
fi

# Desactiver le trap (restauration deja faite)
CLES_SAUVEGARDEES=false

# =============================================================================
# RESUME FINAL
# =============================================================================
echo ""
echo -e "${GRAS}${VERT}╔══════════════════════════════════════════════════════╗${RAZ}"
echo -e "${GRAS}${VERT}║   ✓  Publication GitHub terminee avec succes !      ║${RAZ}"
echo -e "${GRAS}${VERT}╚══════════════════════════════════════════════════════╝${RAZ}"
echo ""
info "Commit  : $(git rev-parse --short HEAD) sur branche '${BRANCHE}'"
info "Remote  : $(git remote get-url origin)"
info "Cles    : masquees sur GitHub, restaurees localement"
echo ""
