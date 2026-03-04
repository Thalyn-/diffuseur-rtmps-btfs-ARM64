#!/usr/bin/env bash
# Forcer UTF-8 independant de la locale SSH
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
# =============================================================================
# diagnostic.sh — Outil de diagnostic et résolution de problèmes
# =============================================================================
# Usage : ./diagnostic.sh [OPTION]
#   --rapide      Diagnostic rapide (30 secondes)
#   --complet     Diagnostic complet avec capture FFmpeg (utile pour le support)
#   --journaux    Afficher les derniers journaux de diffusion
#   --ffmpeg      Tester FFmpeg sur une source BTFS
#   --reseau      Tester la connectivité vers les plateformes
#   --btfs        Diagnostiquer spécifiquement BTFS
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJET_DIR="$(dirname "${SCRIPT_DIR}")"
source "${PROJET_DIR}/conf/orbis.conf"

VERT='\033[0;32m'; ROUGE='\033[0;31m'; ORANGE='\033[0;33m'
BLEU='\033[0;34m'; CYAN='\033[0;36m'; GRAS='\033[1m'; RAZ='\033[0m'

section() { echo -e "\n${GRAS}${CYAN}══ $1 ══${RAZ}"; }
ok()      { echo -e "  ${VERT}✓${RAZ} $1"; }
echec()   { echo -e "  ${ROUGE}✗${RAZ} $1"; }
info()    { echo -e "  ${BLEU}ℹ${RAZ} $1"; }
avert()   { echo -e "  ${ORANGE}⚠${RAZ} $1"; }

RAPPORT="/tmp/orbis-diagnostic-$(date +%Y%m%d_%H%M%S).txt"

# --- Diagnostic système de base ----------------------------------------------
diag_systeme() {
    section "Système"
    echo "  Date         : $(date)"
    echo "  Hostname     : $(hostname)"
    echo "  Architecture : $(uname -m)"
    echo "  Noyau        : $(uname -r)"
    echo "  Distribution : $(. /etc/os-release && echo "${PRETTY_NAME}")"
    echo "  Charge CPU   : $(uptime | sed 's/.*load average: //')"
    echo "  RAM totale   : $(awk '/MemTotal/{printf "%.0f Mo", $2/1024}' /proc/meminfo)"
    echo "  RAM libre    : $(awk '/MemAvailable/{printf "%.0f Mo", $2/1024}' /proc/meminfo)"
    echo "  Espace disque: $(df -h "${REPERTOIRE_JOURNAUX}" | awk 'NR==2{print $4 " disponible sur " $2}')"
    echo "  Température  : $(vcgencmd measure_temp 2>/dev/null || cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "%.1f°C", $1/1000}' || echo "N/A")"
}

# --- Diagnostic FFmpeg -------------------------------------------------------
diag_ffmpeg() {
    section "FFmpeg"
    if command -v "${FFMPEG}" &>/dev/null; then
        "${FFMPEG}" -version 2>&1 | head -3 | sed 's/^/  /'
        info "Encodeurs H.264 disponibles :"
        "${FFMPEG}" -encoders 2>/dev/null | grep -E 'h264|H264|H.264' | sed 's/^/    /'
        info "Protocoles supportés :"
        "${FFMPEG}" -protocols 2>/dev/null | grep -E 'rtmp|http' | tr ',' '\n' | \
            grep -E 'rtmp|http' | xargs | sed 's/^/    /'
    else
        echec "FFmpeg non trouvé : ${FFMPEG}"
    fi
}

# --- Diagnostic BTFS ---------------------------------------------------------
diag_btfs() {
    section "BTFS"
    info "Nœud : ${BTFS_REPO}"
    info "Réseau : chaine-id ${BTFS_CHAINE_ID} ($([ "${BTFS_CHAINE_ID}" = "1029" ] && echo "testnet" || echo "mainnet"))"

    if pgrep -x "btfs" &>/dev/null; then
        ok "Démon BTFS en cours d'exécution (PID: $(pgrep -x btfs | head -1))"
    else
        echec "Démon BTFS non démarré"
        info "Commande de démarrage : btfs daemon --chain-id ${BTFS_CHAINE_ID}"
        return
    fi

    if "${CURL}" -sf --max-time 5 "${BTFS_PASSERELLE}/version" &>/dev/null; then
        local version
        version=$("${CURL}" -sf "${BTFS_PASSERELLE}/version" 2>/dev/null || echo "?")
        ok "API BTFS accessible"
        info "Version : ${version}"
    else
        echec "API BTFS inaccessible (${BTFS_PASSERELLE})"
    fi

    # Test d'accès aux exemples réels
    section "Test de sources BTFS réelles"
    local -a urls_test=(
        "http://127.0.0.1:8080/btfs/QmbQb1kfwEmf4sqCUcccDYHBiuvKAsE4h8LQsQJ13VvZR2"
        "http://127.0.0.1:8080/btfs/QmW7shMNQYCgnvNWntGTZ7cyfr3KD4uPFigXz1wWceCHd5"
    )
    for url in "${urls_test[@]}"; do
        local hash
        hash="$(basename "${url}")"
        printf "  Test %-50s : " "${hash:0:20}..."
        local http_code
        http_code=$("${CURL}" -sf -o /dev/null --max-time 20 -w "%{http_code}" "${url}" 2>/dev/null || echo "000")
        if [[ "${http_code}" =~ ^2 ]]; then
            echo -e "${VERT}HTTP ${http_code} ✓${RAZ}"
        elif [[ "${http_code}" =~ ^3 ]]; then
            echo -e "${ORANGE}HTTP ${http_code} (redirection)${RAZ}"
        else
            echo -e "${ROUGE}HTTP ${http_code} ✗${RAZ}"
        fi
    done
}

# --- Diagnostic réseau -------------------------------------------------------
diag_reseau() {
    section "Connectivité réseau"

    # DLive RTMP
    printf "  DLive RTMP (stream.dlive.tv:1935) : "
    if timeout 5 bash -c ">/dev/tcp/stream.dlive.tv/1935" 2>/dev/null; then
        echo -e "${VERT}accessible ✓${RAZ}"
    else
        echo -e "${ROUGE}inaccessible ✗${RAZ}"
        avert "Vérifiez que le port 1935 n'est pas bloqué par votre FAI"
    fi

    # Kick RTMPS
    printf "  Kick RTMPS (fa723fc1b171....:443) : "
    if timeout 5 bash -c ">/dev/tcp/fa723fc1b171.global-contribute.live-video.net/443" 2>/dev/null; then
        echo -e "${VERT}accessible ✓${RAZ}"
    else
        echo -e "${ROUGE}inaccessible ✗${RAZ}"
    fi

    # Stunnel local
    printf "  Stunnel local (127.0.0.1:${STUNNEL_PORT_LOCAL})   : "
    if timeout 2 bash -c ">/dev/tcp/127.0.0.1/${STUNNEL_PORT_LOCAL}" 2>/dev/null; then
        echo -e "${VERT}en écoute ✓${RAZ}"
    else
        echo -e "${ROUGE}non disponible ✗${RAZ} (stunnel4 doit être actif)"
    fi

    # nginx-rtmp local
    printf "  nginx-rtmp local (127.0.0.1:${NGINX_PORT_RTMP})  : "
    if timeout 2 bash -c ">/dev/tcp/127.0.0.1/${NGINX_PORT_RTMP}" 2>/dev/null; then
        echo -e "${VERT}en écoute ✓${RAZ}"
    else
        echo -e "${ROUGE}non disponible ✗${RAZ} (nginx doit être actif)"
    fi

    # Débit internet (test simple)
    section "Débit internet (estimation)"
    info "Test de débit en upload (10 secondes)..."
    local debit
    debit=$("${CURL}" -sf --max-time 10 --upload-file /dev/zero \
            "https://speed.cloudflare.com/__up" --limit-rate 20M 2>/dev/null | \
            grep -oP '"bandwidth":\K[0-9]+' || echo "0")
    if (( debit > 0 )); then
        local debit_mbps=$(( debit / 1000000 ))
        info "Débit estimé : ~${debit_mbps} Mbps"
        if (( debit_mbps >= 8 )); then
            ok "Débit suffisant pour multi-plateforme (Kick 6Mbps + DLive 4.5Mbps)"
        elif (( debit_mbps >= 5 )); then
            avert "Débit limité : préférez une seule plateforme à la fois"
        else
            echec "Débit insuffisant pour la diffusion 1080p"
        fi
    else
        avert "Impossible de mesurer le débit (test ignoré)"
    fi
}

# --- Test FFmpeg sur source BTFS ---------------------------------------------
test_ffmpeg_btfs() {
    section "Test FFmpeg → Source BTFS (5 secondes)"
    local url_test="http://127.0.0.1:8080/btfs/QmbQb1kfwEmf4sqCUcccDYHBiuvKAsE4h8LQsQJ13VvZR2"

    info "Source : ${url_test}"
    info "Test d'un transcodage de 5 secondes vers /dev/null..."

    if "${FFMPEG}" -hide_banner -loglevel warning \
        -re -i "${url_test}" \
        -t 5 \
        -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:black" \
        -c:v libx264 -preset veryfast -b:v 4500k \
        -c:a aac -b:a 160k \
        -f null /dev/null 2>&1 | tee -a "${RAPPORT}"; then
        ok "Transcodage test réussi"
    else
        echec "Erreur lors du transcodage test (voir les logs ci-dessus)"
    fi
}

# --- Afficher les journaux ---------------------------------------------------
cmd_journaux() {
    section "Derniers journaux de diffusion"
    local dernier
    dernier=$(ls -t "${REPERTOIRE_JOURNAUX}"/diffusion_*.log 2>/dev/null | head -1 || echo "")
    if [[ -z "${dernier}" ]]; then
        avert "Aucun journal de diffusion trouvé dans ${REPERTOIRE_JOURNAUX}"
        return
    fi
    info "Journal : ${dernier}"
    echo ""
    tail -50 "${dernier}"
}

# --- Rapport complet ---------------------------------------------------------
generer_rapport() {
    {
        echo "# Rapport de diagnostic Orbis Alternis"
        echo "# Généré le : $(date)"
        echo "# ======================================"
        diag_systeme
        diag_ffmpeg
        diag_btfs
        diag_reseau
    } > "${RAPPORT}"
    ok "Rapport sauvegardé : ${RAPPORT}"
    info "Incluez ce fichier si vous demandez de l'aide."
}

# --- Point d'entrée ----------------------------------------------------------
case "${1:---rapide}" in
    --rapide|-r)
        diag_systeme
        diag_ffmpeg
        diag_btfs
        ;;
    --complet|-c)
        diag_systeme
        diag_ffmpeg
        diag_btfs
        diag_reseau
        test_ffmpeg_btfs
        generer_rapport
        ;;
    --journaux|-j)
        cmd_journaux
        ;;
    --ffmpeg|-f)
        test_ffmpeg_btfs
        ;;
    --reseau|-n)
        diag_reseau
        ;;
    --btfs|-b)
        diag_btfs
        ;;
    --aide|-h|help)
        grep '^#' "${BASH_SOURCE[0]}" | grep -A10 'Usage' | sed 's/^# \?//'
        ;;
    *)
        echo "Option inconnue : $1. Utiliser --aide pour l'aide."
        exit 1
        ;;
esac
