#!/usr/bin/env bash
# =============================================================================
# diffuser.sh — Script principal de diffusion Orbis Alternis
# =============================================================================
# Usage : ./diffuser.sh [OPTIONS]
#
#   -l <fichier>    Liste de lecture à utiliser (défaut : ldl/ldl_tot.txt)
#   -p <cible>      Plateforme : dlive | kick | toutes (défaut : toutes)
#   -m              Mélanger aléatoirement la liste de lecture
#   -b              Forcer le bouclage (écrase conf/orbis.conf)
#   -n              Forcer lecture unique sans boucle
#   -f              Activer le filigrane (logo)
#   -w              Activer la surcouche webcam
#   -h              Afficher ce message d'aide
#
# Exemples :
#   ./diffuser.sh
#   ./diffuser.sh -l ldl/ldl_dystopies.txt -p kick -m
#   ./diffuser.sh -l ldl/ldl_tot.txt -p toutes -f
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# --- Chemin absolu du projet -------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJET_DIR="$(dirname "${SCRIPT_DIR}")"

# --- Chargement de la configuration ------------------------------------------
FICHIER_CONF="${PROJET_DIR}/conf/orbis.conf"
if [[ ! -f "${FICHIER_CONF}" ]]; then
    echo "[ERREUR] Fichier de configuration introuvable : ${FICHIER_CONF}" >&2
    exit 1
fi
# shellcheck source=../conf/orbis.conf
source "${FICHIER_CONF}"

# --- Journalisation ----------------------------------------------------------
mkdir -p "${REPERTOIRE_JOURNAUX}"
JOURNAL="${REPERTOIRE_JOURNAUX}/diffusion_$(date +%Y%m%d_%H%M%S).log"

_log() {
    local niveau="$1"; shift
    local message="$*"
    local horodatage
    horodatage="$(date +'%Y-%m-%d %H:%M:%S')"
    printf "[%s] [%-6s] %s\n" "${horodatage}" "${niveau}" "${message}" | tee -a "${JOURNAL}"
}
info()    { _log "INFO"   "$@"; }
ok()      { _log "OK"     "$@"; }
avert()   { _log "AVERT"  "$@"; }
erreur()  { _log "ERREUR" "$@"; }
debug()   { [[ "${NIVEAU_JOURNAL}" == "DEBUG" ]] && _log "DEBUG" "$@" || true; }

# --- Gestion du signal d'arrêt -----------------------------------------------
PID_FFMPEG=""
PID_NGINX=""

nettoyer() {
    info "Signal reçu — arrêt propre en cours..."
    [[ -n "${PID_FFMPEG}" ]] && kill -SIGTERM "${PID_FFMPEG}" 2>/dev/null && wait "${PID_FFMPEG}" 2>/dev/null || true
    # Restauration de l'ancienne config nginx si nécessaire
    if [[ -f "${PROJET_DIR}/conf/nginx-rtmp.conf.bak" ]]; then
        sudo mv "${PROJET_DIR}/conf/nginx-rtmp.conf.bak" "${PROJET_DIR}/conf/nginx-rtmp.conf" 2>/dev/null || true
        sudo systemctl reload nginx 2>/dev/null || true
    fi
    info "Diffusion arrêtée proprement."
    exit 0
}
trap nettoyer SIGINT SIGTERM

# --- Valeurs par défaut (surchargées par les options) -----------------------
LDL_FICHIER="${REPERTOIRE_LDL}/ldl_tot.txt"
CIBLE_PLATEFORME="toutes"
OPT_MELANGE=false
OPT_BOUCLE="${BOUCLE}"
OPT_FILIGRANE="${FILIGRANE_ACTIF}"
OPT_WEBCAM="${WEBCAM_ACTIF}"

# --- Analyse des arguments ---------------------------------------------------
usage() {
    grep '^#' "${BASH_SOURCE[0]}" | grep -A50 'Usage' | sed 's/^# \?//'
    exit 0
}

while getopts ":l:p:mbnfwh" opt; do
    case "${opt}" in
        l) LDL_FICHIER="${OPTARG}" ;;
        p) CIBLE_PLATEFORME="${OPTARG}" ;;
        m) OPT_MELANGE=true ;;
        b) OPT_BOUCLE=true ;;
        n) OPT_BOUCLE=false ;;
        f) OPT_FILIGRANE=true ;;
        w) OPT_WEBCAM=true ;;
        h) usage ;;
        :) erreur "Option -${OPTARG} requiert un argument."; exit 1 ;;
        \?) erreur "Option inconnue : -${OPTARG}"; exit 1 ;;
    esac
done

# --- Validation des prérequis ------------------------------------------------
verifier_dependances() {
    local manquants=()
    for outil in "${FFMPEG}" "${FFPROBE}" "${CURL}" "${STUNNEL}"; do
        [[ ! -x "${outil}" ]] && manquants+=("${outil}")
    done
    if ! command -v nginx &>/dev/null; then
        manquants+=("nginx")
    fi
    if (( ${#manquants[@]} > 0 )); then
        erreur "Outils manquants : ${manquants[*]}"
        erreur "Consultez docs/INSTALLATION.md pour les installer."
        exit 1
    fi
    ok "Toutes les dépendances sont présentes."
}

verifier_btfs() {
    info "Vérification du démon BTFS..."
    if ! "${CURL}" -sf --max-time 5 "${BTFS_PASSERELLE}/version" &>/dev/null; then
        avert "La passerelle BTFS ne répond pas. Tentative de démarrage..."
        eval "${BTFS_DAEMON_CMD}" &>/dev/null &
        sleep "${BTFS_DELAI_DEMARRAGE}"
        if ! "${CURL}" -sf --max-time 10 "${BTFS_PASSERELLE}/version" &>/dev/null; then
            erreur "Impossible de joindre la passerelle BTFS (${BTFS_PASSERELLE})"
            erreur "Vérifiez : btfs daemon --chain-id ${BTFS_CHAINE_ID}"
            exit 1
        fi
    fi
    ok "Passerelle BTFS accessible : ${BTFS_PASSERELLE}"
}

verifier_cles_flux() {
    local ok_flux=true
    if [[ "${CIBLE_PLATEFORME}" =~ ^(dlive|toutes)$ ]] && [[ -z "${DLIVE_CLE_FLUX}" ]]; then
        erreur "Clé de flux DLive manquante (DLIVE_CLE_FLUX dans orbis.conf)"
        ok_flux=false
    fi
    if [[ "${CIBLE_PLATEFORME}" =~ ^(kick|toutes)$ ]] && [[ -z "${KICK_CLE_FLUX}" ]]; then
        erreur "Clé de flux Kick manquante (KICK_CLE_FLUX dans orbis.conf)"
        ok_flux=false
    fi
    [[ "${ok_flux}" == "false" ]] && exit 1
    ok "Clés de flux vérifiées."
}

verifier_ldl() {
    if [[ ! -f "${LDL_FICHIER}" ]]; then
        erreur "Liste de lecture introuvable : ${LDL_FICHIER}"
        exit 1
    fi
    local nb_entrees
    nb_entrees=$(grep -cE '^https?://' "${LDL_FICHIER}" 2>/dev/null || echo 0)
    if (( nb_entrees == 0 )); then
        erreur "La liste de lecture est vide ou ne contient pas d'URL valides."
        exit 1
    fi
    ok "Liste de lecture chargée : ${LDL_FICHIER} (${nb_entrees} entrées)"
}

# --- Configuration dynamique de nginx-rtmp -----------------------------------
generer_config_nginx() {
    info "Génération de la configuration nginx-rtmp..."
    local conf_src="${PROJET_DIR}/conf/nginx-rtmp.conf"
    local conf_dst="/etc/nginx/sites-enabled/orbis-rtmp.conf"
    local conf_tmp
    conf_tmp="$(mktemp)"

    sed \
        -e "s|NGINX_PORT_RTMP|${NGINX_PORT_RTMP}|g" \
        -e "s|NGINX_CHEMIN_APPLICATION|${NGINX_CHEMIN_APPLICATION}|g" \
        -e "s|DLIVE_SERVEUR|${DLIVE_SERVEUR}|g" \
        -e "s|DLIVE_CLE_FLUX|${DLIVE_CLE_FLUX}|g" \
        -e "s|STUNNEL_PORT_LOCAL|${STUNNEL_PORT_LOCAL}|g" \
        -e "s|KICK_CLE_FLUX|${KICK_CLE_FLUX}|g" \
        "${conf_src}" > "${conf_tmp}"

    # Désactiver la ligne DLive si non actif
    if [[ "${DLIVE_ACTIF}" != "true" ]]; then
        sed -i '/push.*dlive/d' "${conf_tmp}"
        info "DLive désactivé dans la configuration nginx."
    fi
    # Désactiver la ligne Kick si non actif
    if [[ "${KICK_ACTIF}" != "true" ]]; then
        sed -i '/push.*stunnel/d; /push.*11935/d' "${conf_tmp}"
        info "Kick désactivé dans la configuration nginx."
    fi

    sudo cp "${conf_tmp}" "${conf_dst}"
    rm -f "${conf_tmp}"
    sudo nginx -t 2>>"${JOURNAL}" || { erreur "Configuration nginx invalide."; exit 1; }
    sudo systemctl reload nginx
    ok "nginx-rtmp reconfigurée et rechargée."
}

# --- Démarrage de Stunnel ----------------------------------------------------
demarrer_stunnel() {
    if [[ "${KICK_ACTIF}" != "true" ]]; then
        debug "Kick inactif — Stunnel non démarré."
        return 0
    fi
    info "Démarrage de Stunnel (tunnel RTMPS → Kick)..."
    sudo cp "${PROJET_DIR}/conf/stunnel-kick.conf" /etc/stunnel/stunnel.conf
    sudo systemctl restart stunnel4
    sleep 2
    if ! systemctl is-active --quiet stunnel4; then
        erreur "Stunnel n'a pas pu démarrer. Vérifiez /var/log/stunnel4/stunnel.log"
        exit 1
    fi
    ok "Stunnel actif sur le port local ${STUNNEL_PORT_LOCAL} → Kick RTMPS"
}

# --- Construction des filtres vidéo FFmpeg -----------------------------------
construire_filtre_video() {
    # Mise à l'échelle 1080p max avec bandes noires (letterbox/pillarbox)
    local vf="scale=w=${LARGEUR_MAX}:h=${HAUTEUR_MAX}:force_original_aspect_ratio=decrease,"
    vf+="pad=${LARGEUR_MAX}:${HAUTEUR_MAX}:(ow-iw)/2:(oh-ih)/2:black"

    # Ajout du filigrane si activé
    if [[ "${OPT_FILIGRANE}" == "true" ]] && [[ -f "${FILIGRANE_IMAGE}" ]]; then
        vf+=",movie=${FILIGRANE_IMAGE},colorchannelmixer=aa=${FILIGRANE_OPACITE}[logo]"
        vf+=";[in][logo]overlay=${FILIGRANE_POSITION}[out]"
    fi

    # Ajout de la surcouche webcam si activée
    if [[ "${OPT_WEBCAM}" == "true" ]]; then
        # La webcam est ajoutée comme entrée supplémentaire dans la commande FFmpeg
        WEBCAM_FILTRE_ACTIF=true
    fi

    echo "${vf}"
}

# --- Construction de la commande FFmpeg principale ---------------------------
# Paramètre $1 : URL BTFS de la vidéo à diffuser
diffuser_video() {
    local url_source="$1"
    local titre="${2:-inconnu}"
    local bitrate_video
    local bitrate_audio
    local url_rtmp_local="rtmp://127.0.0.1:${NGINX_PORT_RTMP}/${NGINX_CHEMIN_APPLICATION}/orbis"

    # Bitrate = le minimum entre DLive et Kick (si les deux actifs)
    if [[ "${CIBLE_PLATEFORME}" == "dlive" ]]; then
        bitrate_video="${DLIVE_BITRATE_VIDEO}"
        bitrate_audio="${DLIVE_BITRATE_AUDIO}"
    elif [[ "${CIBLE_PLATEFORME}" == "kick" ]]; then
        bitrate_video="${KICK_BITRATE_VIDEO}"
        bitrate_audio="${KICK_BITRATE_AUDIO}"
    else
        # Multi-plateforme : on prend le max compatible (Kick est plus exigeant)
        bitrate_video="${KICK_BITRATE_VIDEO}"
        bitrate_audio="${KICK_BITRATE_AUDIO}"
    fi

    local filtre_video
    filtre_video="$(construire_filtre_video)"
    WEBCAM_FILTRE_ACTIF="${WEBCAM_FILTRE_ACTIF:-false}"

    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    info "Diffusion : ${titre}"
    info "Source    : ${url_source}"
    info "Cible     : ${CIBLE_PLATEFORME} | Débit vidéo : ${bitrate_video}k | Audio : ${bitrate_audio}k"
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # --- Construction de la commande FFmpeg ----------------------------------
    local cmd_ffmpeg=(
        "${FFMPEG}"
        -hide_banner
        -loglevel warning
        -stats
        # Lecture de la source BTFS à vitesse native (temps réel)
        -re
        -i "${url_source}"
    )

    # Ajout de la webcam comme seconde entrée si activée
    if [[ "${WEBCAM_FILTRE_ACTIF}" == "true" ]]; then
        cmd_ffmpeg+=(
            -f v4l2
            -framerate "${WEBCAM_DEBIT_IMAGES}"
            -video_size "${WEBCAM_LARGEUR}x${WEBCAM_HAUTEUR}"
            -i "${WEBCAM_PERIPHERIQUE}"
        )
    fi

    # Paramètres d'encodage vidéo
    cmd_ffmpeg+=(
        -vf "${filtre_video}"
        -c:v "${ENCODEUR_VIDEO}"
    )

    # Paramètres spécifiques à l'encodeur
    if [[ "${ENCODEUR_VIDEO}" == "libx264" ]]; then
        cmd_ffmpeg+=(
            -preset "${PRESET_ENCODAGE}"
            -profile:v "${PROFIL_H264}"
            -level:v "${NIVEAU_H264}"
            -b:v "${bitrate_video}k"
            -maxrate "${bitrate_video}k"
            -bufsize "$((bitrate_video * 2))k"
            -x264-params "nal-hrd=cbr:force-cfr=1"
        )
    elif [[ "${ENCODEUR_VIDEO}" == "h264_v4l2m2m" ]]; then
        # Encodeur matériel du Raspberry Pi 4
        cmd_ffmpeg+=(
            -b:v "${bitrate_video}k"
            -maxrate "${bitrate_video}k"
            -bufsize "$((bitrate_video * 2))k"
            -num_capture_buffers 64
        )
    fi

    # Paramètres communs vidéo/audio
    cmd_ffmpeg+=(
        -g "${GOP}"
        -keyint_min "${GOP}"
        -sc_threshold 0
        -r "${DEBIT_IMAGES}"
        # Audio
        -c:a aac
        -b:a "${bitrate_audio}k"
        -ar 44100
        -ac 2
        # Sortie vers nginx-rtmp local
        -f flv
        "${url_rtmp_local}"
    )

    debug "Commande : ${cmd_ffmpeg[*]}"

    # Lancement de FFmpeg en arrière-plan pour pouvoir capturer son PID
    "${cmd_ffmpeg[@]}" 2>>"${JOURNAL}" &
    PID_FFMPEG=$!

    # Attente de la fin de FFmpeg
    local code_retour=0
    wait "${PID_FFMPEG}" || code_retour=$?
    PID_FFMPEG=""

    if (( code_retour == 0 )); then
        ok "Vidéo terminée : ${titre}"
    else
        avert "FFmpeg s'est terminé avec le code ${code_retour} pour : ${titre}"
    fi
    return ${code_retour}
}

# --- Chargement et traitement de la liste de lecture -------------------------
lire_liste_lecture() {
    local fichier="$1"
    local -a urls=()
    local -a titres=()

    while IFS= read -r ligne; do
        # Ignorer les lignes vides et commentaires simples
        [[ -z "${ligne}" ]] && continue
        [[ "${ligne}" =~ ^[[:space:]]*# ]] && continue

        # Extraire l'URL et le titre optionnel (après #)
        local url titre
        url="$(echo "${ligne}" | sed 's/[[:space:]]*#.*//' | xargs)"
        titre="$(echo "${ligne}" | grep -oP '(?<=#\s?).*' | xargs || echo "Sans titre")"
        [[ -z "${titre}" ]] && titre="$(basename "${url}")"

        # Vérifier que c'est bien une URL HTTP(S)
        if [[ "${url}" =~ ^https?:// ]]; then
            urls+=("${url}")
            titres+=("${titre}")
        fi
    done < "${fichier}"

    # Mélange aléatoire si demandé
    if [[ "${OPT_MELANGE}" == "true" ]]; then
        info "Mélange aléatoire de la liste de lecture..."
        local -a indices_melanges
        mapfile -t indices_melanges < <(
            for i in "${!urls[@]}"; do echo "$i"; done | shuf
        )
        local -a urls_tmp=() titres_tmp=()
        for i in "${indices_melanges[@]}"; do
            urls_tmp+=("${urls[$i]}")
            titres_tmp+=("${titres[$i]}")
        done
        urls=("${urls_tmp[@]}")
        titres=("${titres_tmp[@]}")
    fi

    # Écriture dans des fichiers temporaires pour le bouclage
    local tmp_urls tmp_titres
    tmp_urls="$(mktemp)"
    tmp_titres="$(mktemp)"
    printf '%s\n' "${urls[@]}" > "${tmp_urls}"
    printf '%s\n' "${titres[@]}" > "${tmp_titres}"
    echo "${tmp_urls}:${tmp_titres}"
}

# --- Boucle principale de diffusion ------------------------------------------
boucle_principale() {
    info "============================================================"
    info "  Orbis Alternis — Démarrage de la diffusion"
    info "  Liste     : $(basename "${LDL_FICHIER}")"
    info "  Plateforme: ${CIBLE_PLATEFORME}"
    info "  Bouclage  : ${OPT_BOUCLE} | Mélange : ${OPT_MELANGE}"
    info "============================================================"

    local tour=1
    local continuer=true

    while [[ "${continuer}" == "true" ]]; do
        info "--- Tour n°${tour} de la liste de lecture ---"

        local fichiers_tmp
        fichiers_tmp="$(lire_liste_lecture "${LDL_FICHIER}")"
        local tmp_urls="${fichiers_tmp%%:*}"
        local tmp_titres="${fichiers_tmp##*:}"

        local index=0
        local total
        total="$(wc -l < "${tmp_urls}")"

        while IFS= read -r url && IFS= read -r titre <&3; do
            index=$(( index + 1 ))
            info "[${index}/${total}] Préparation : ${titre}"

            # Vérification de l'accessibilité de la source BTFS
            local tentative=1
            local source_ok=false
            while (( tentative <= TENTATIVES_RECONNEXION )); do
                if "${CURL}" -sf --max-time 15 --head "${url}" &>/dev/null; then
                    source_ok=true
                    break
                fi
                avert "Source inaccessible (tentative ${tentative}/${TENTATIVES_RECONNEXION}) : ${url}"
                sleep "${DELAI_RECONNEXION}"
                tentative=$(( tentative + 1 ))
            done

            if [[ "${source_ok}" == "false" ]]; then
                erreur "Source inaccessible après ${TENTATIVES_RECONNEXION} tentatives. Passage à la suivante."
                continue
            fi

            # Diffusion de la vidéo
            local essai=1
            local diffusion_ok=false
            while (( essai <= TENTATIVES_RECONNEXION )); do
                if diffuser_video "${url}" "${titre}"; then
                    diffusion_ok=true
                    break
                fi
                avert "Erreur de diffusion (essai ${essai}/${TENTATIVES_RECONNEXION}). Nouvelle tentative dans ${DELAI_RECONNEXION}s..."
                sleep "${DELAI_RECONNEXION}"
                essai=$(( essai + 1 ))
            done

            [[ "${diffusion_ok}" == "false" ]] && erreur "Échec définitif pour : ${titre}"

            # Pause entre deux vidéos
            if (( index < total )); then
                info "Pause de ${DELAI_ENTRE_VIDEOS}s avant la prochaine vidéo..."
                sleep "${DELAI_ENTRE_VIDEOS}"
            fi

        done < "${tmp_urls}" 3< "${tmp_titres}"

        rm -f "${tmp_urls}" "${tmp_titres}"

        # Décision de bouclage
        if [[ "${OPT_BOUCLE}" == "true" ]]; then
            tour=$(( tour + 1 ))
            info "Fin du tour ${tour} — Relance de la liste de lecture."
            sleep "${DELAI_ENTRE_VIDEOS}"
        else
            continuer=false
        fi
    done

    info "Diffusion terminée (liste épuisée, bouclage désactivé)."
}

# --- Point d'entrée principal ------------------------------------------------
main() {
    info "Orbis Alternis — Diffuseur RTMPS/BTFS v1.0 (ARM64)"
    info "Configuration : ${FICHIER_CONF}"

    verifier_dependances
    verifier_cles_flux
    verifier_btfs
    verifier_ldl

    generer_config_nginx
    demarrer_stunnel

    # Nettoyage automatique des anciens journaux
    find "${REPERTOIRE_JOURNAUX}" -name "*.log" -mtime "+${CONSERVATION_JOURNAUX}" -delete 2>/dev/null || true

    boucle_principale
}

main "$@"
