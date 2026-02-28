#!/usr/bin/env bash
# Forcer UTF-8 independant de la locale SSH
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
# =============================================================================
# verifier-systeme.sh — Vérification complète du système avant diffusion
# =============================================================================
# Vérifie que tous les composants nécessaires sont installés et configurés.
# À lancer après installation (cf. docs/INSTALLATION.md).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJET_DIR="$(dirname "${SCRIPT_DIR}")"
source "${PROJET_DIR}/conf/orbis.conf"

# --- Couleurs terminal -------------------------------------------------------
VERT='\033[0;32m'; ROUGE='\033[0;31m'; ORANGE='\033[0;33m'
BLEU='\033[0;34m'; GRAS='\033[1m'; RAZ='\033[0m'

ok()     { echo -e "  ${VERT}✓${RAZ}  $1"; }
echec()  { echo -e "  ${ROUGE}✗${RAZ}  $1"; ERREURS=$(( ERREURS + 1 )); }
avert()  { echo -e "  ${ORANGE}⚠${RAZ}  $1"; AVERTISSEMENTS=$(( AVERTISSEMENTS + 1 )); }
titre()  { echo -e "\n${GRAS}${BLEU}▶ $1${RAZ}"; }

ERREURS=0
AVERTISSEMENTS=0

# --- 1. Architecture ---------------------------------------------------------
titre "Architecture & système"
ARCH=$(uname -m)
if [[ "${ARCH}" == "aarch64" ]]; then
    ok "Architecture ARM64 (aarch64) — Raspberry Pi 4 détecté"
else
    avert "Architecture : ${ARCH} (ARM64 attendu pour la production)"
fi

DISTRIB=$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME}" || echo "Inconnue")
ok "Distribution : ${DISTRIB}"

RAM_MB=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)
if (( RAM_MB >= 3800 )); then
    ok "Mémoire vive : ${RAM_MB} Mo (suffisant)"
elif (( RAM_MB >= 2000 )); then
    avert "Mémoire vive : ${RAM_MB} Mo (minimum recommandé : 4 Go)"
else
    echec "Mémoire vive insuffisante : ${RAM_MB} Mo"
fi

# --- 2. Dépendances logicielles ----------------------------------------------
titre "Dépendances logicielles"

verifier_binaire() {
    local binaire="$1" description="$2"
    if command -v "${binaire}" &>/dev/null || [[ -x "${binaire}" ]]; then
        local version
        version=$("${binaire}" --version 2>&1 | head -1 | sed 's/.*version /v/;s/ .*//')
        ok "${description} : ${version}"
    else
        echec "${description} introuvable : ${binaire}"
    fi
}

verifier_binaire "${FFMPEG}"   "FFmpeg"
verifier_binaire "${FFPROBE}"  "FFprobe"
verifier_binaire "${CURL}"     "cURL"
verifier_binaire "${STUNNEL}"  "Stunnel"
verifier_binaire "nginx"       "Nginx"
verifier_binaire "btfs"        "BTFS"

# Vérifier le module nginx-rtmp
if nginx -V 2>&1 | grep -q 'nginx-rtmp\|ngx_rtmp'; then
    ok "Module nginx-rtmp : présent"
elif [[ -f /usr/lib/nginx/modules/ngx_rtmp_module.so ]]; then
    ok "Module nginx-rtmp : présent (libnginx-mod-rtmp)"
else
    echec "Module nginx-rtmp manquant — sudo apt install libnginx-mod-rtmp"
fi

# Vérifier le support RTMPS de FFmpeg
if "${FFMPEG}" -protocols 2>/dev/null | grep -q 'rtmps'; then
    ok "FFmpeg supporte RTMPS (secours sans Stunnel)"
else
    avert "FFmpeg ne supporte pas RTMPS nativement (Stunnel obligatoire pour Kick)"
fi

# Encodeur matériel Pi4
if [[ -e /dev/video10 ]] || [[ -e /dev/video11 ]]; then
    ok "Encodeur matériel H.264 V4L2 M2M disponible (h264_v4l2m2m)"
else
    avert "Encodeur matériel non détecté (utilisation de libx264 logiciel)"
fi

# --- 3. Services système -----------------------------------------------------
titre "Services système"

verifier_service() {
    local service="$1"
    if systemctl is-active --quiet "${service}" 2>/dev/null; then
        ok "Service ${service} : actif"
    elif systemctl is-enabled --quiet "${service}" 2>/dev/null; then
        avert "Service ${service} : inactif mais activé au démarrage"
    else
        echec "Service ${service} : inactif"
    fi
}

verifier_service "nginx"
verifier_service "stunnel4"

# --- 4. BTFS -----------------------------------------------------------------
titre "BTFS (BitTorrent File System)"

if "${CURL}" -sf --max-time 5 "${BTFS_API}/version" &>/dev/null; then
    local_version=$("${CURL}" -sf --max-time 5 "${BTFS_API}/version" | grep -oP '"Version":"\K[^"]+' || echo "?")
    ok "API BTFS accessible : ${BTFS_API} (v${local_version})"

    # Vérifier la connectivité réseau BTFS
    nb_pairs=$("${CURL}" -sf --max-time 10 "http://127.0.0.1:5001/api/v1/swarm/peers" 2>/dev/null | \
               grep -oP '"Addr"' | wc -l || echo 0)
    if (( nb_pairs > 0 )); then
        ok "Pairs BTFS connectés : ${nb_pairs}"
    else
        avert "Aucun pair BTFS connecté (réseau ou synchronisation en cours)"
    fi

    # Test d'accès à un fichier réel
    url_test="http://127.0.0.1:8080/btfs/QmbQb1kfwEmf4sqCUcccDYHBiuvKAsE4h8LQsQJ13VvZR2"
    if "${CURL}" -sf --max-time 15 --head "${url_test}" &>/dev/null; then
        ok "Accès fichier BTFS : opérationnel"
    else
        avert "Test fichier BTFS : en attente (normal si fichier non encore mis en cache)"
    fi
else
    echec "API BTFS inaccessible. Lancer : btfs daemon --chain-id ${BTFS_CHAINE_ID}"
fi

# --- 5. Configuration du projet ----------------------------------------------
titre "Configuration Orbis Alternis"

if [[ -f "${FICHIER_CONF:-${PROJET_DIR}/conf/orbis.conf}" ]]; then
    ok "Fichier de configuration : présent"
else
    echec "Fichier de configuration manquant : ${PROJET_DIR}/conf/orbis.conf"
fi

# Vérifier les clés de flux (présentes mais ne pas les afficher)
if [[ -n "${DLIVE_CLE_FLUX:-}" ]]; then
    ok "Clé de flux DLive : renseignée (${#DLIVE_CLE_FLUX} caractères)"
else
    echec "Clé de flux DLive manquante (DLIVE_CLE_FLUX dans orbis.conf)"
fi

if [[ -n "${KICK_CLE_FLUX:-}" ]]; then
    ok "Clé de flux Kick : renseignée (${#KICK_CLE_FLUX} caractères)"
else
    echec "Clé de flux Kick manquante (KICK_CLE_FLUX dans orbis.conf)"
fi

# Vérifier les répertoires
for rep in "${REPERTOIRE_LDL}" "${REPERTOIRE_IMG}" "${REPERTOIRE_JOURNAUX}"; do
    if [[ -d "${rep}" ]]; then
        ok "Répertoire : ${rep}"
    else
        echec "Répertoire manquant : ${rep}"
    fi
done

# Vérifier les listes de lecture
nb_ldl=$(ls "${REPERTOIRE_LDL}"/ldl_*.txt 2>/dev/null | wc -l)
if (( nb_ldl > 0 )); then
    nb_total=$(grep -hcE '^https?://' "${REPERTOIRE_LDL}"/ldl_*.txt 2>/dev/null | \
               awk '{s+=$1}END{print s+0}')
    ok "Listes de lecture : ${nb_ldl} fichier(s), ${nb_total} entrée(s) au total"
else
    avert "Aucune liste de lecture trouvée dans ${REPERTOIRE_LDL}"
fi

# --- 6. Connectivité réseau --------------------------------------------------
titre "Connectivité réseau"

verifier_connectivite() {
    local hote="$1" description="$2" port="${3:-443}"
    if "${CURL}" -sf --max-time 10 --connect-timeout 5 \
       "https://${hote}" &>/dev/null 2>&1 || \
       timeout 5 bash -c ">/dev/tcp/${hote}/${port}" 2>/dev/null; then
        ok "${description} (${hote}:${port}) : joignable"
    else
        avert "${description} (${hote}:${port}) : non joignable depuis ce réseau"
    fi
}

verifier_connectivite "stream.dlive.tv" "Serveur DLive" 1935
verifier_connectivite "fa723fc1b171.global-contribute.live-video.net" "Serveur Kick" 443

# --- Résumé final ------------------------------------------------------------
echo -e "\n${GRAS}════════════════════════════════════════${RAZ}"
if (( ERREURS == 0 && AVERTISSEMENTS == 0 )); then
    echo -e "${VERT}${GRAS}  ✓ Système prêt pour la diffusion${RAZ}"
elif (( ERREURS == 0 )); then
    echo -e "${ORANGE}${GRAS}  ⚠ Prêt avec ${AVERTISSEMENTS} avertissement(s)${RAZ}"
else
    echo -e "${ROUGE}${GRAS}  ✗ ${ERREURS} erreur(s) bloquante(s) — voir ci-dessus${RAZ}"
fi
echo -e "${GRAS}════════════════════════════════════════${RAZ}\n"

exit ${ERREURS}
