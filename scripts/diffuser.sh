#!/usr/bin/env bash
# =============================================================================
# diffuser.sh -- Script principal de diffusion Orbis Alternis
# =============================================================================
# Usage : ./diffuser.sh [OPTIONS]
#
#   -l <fichier>    Liste de lecture (defaut : ldl/ldl_tot.txt)
#   -p <cible>      Plateforme : dlive | kick | toutes (defaut : toutes)
#   -m              Melanger aleatoirement la liste
#   -b              Forcer le bouclage
#   -n              Forcer lecture unique sans boucle
#   -f              Activer le filigrane (logo)
#   -w              Activer la surcouche webcam
#   -h              Afficher l'aide
#
# Exemples :
#   ./diffuser.sh
#   ./diffuser.sh -l ldl/ldl_dystopies.txt -p kick -m
#   ./diffuser.sh -l ldl/ldl_tot.txt -p toutes -f
# =============================================================================

# --- Encodage et locale (evite les problemes d'affichage UTF-8 en SSH) -------
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

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

# --- Gestion du signal d'arret -----------------------------------------------
PID_FFMPEG=""
FIFO_CONCAT=""

nettoyer() {
    info "Signal recu -- arret propre en cours..."
    [[ -n "${PID_FFMPEG}" ]] && kill -SIGTERM "${PID_FFMPEG}" 2>/dev/null && wait "${PID_FFMPEG}" 2>/dev/null || true
    [[ -n "${FIFO_CONCAT}" ]] && rm -f "${FIFO_CONCAT}" 2>/dev/null || true
    info "Diffusion arretee proprement."
    exit 0
}
trap nettoyer SIGINT SIGTERM

# --- Valeurs par defaut ------------------------------------------------------
LDL_FICHIER="${REPERTOIRE_LDL}/ldl_tot.txt"
CIBLE_PLATEFORME="toutes"
OPT_MELANGE=false
OPT_BOUCLE="${BOUCLE}"
OPT_FILIGRANE="${FILIGRANE_ACTIF}"
OPT_WEBCAM="${WEBCAM_ACTIF}"
WEBCAM_FILTRE_ACTIF=false

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

# --- Validation des prerequis ------------------------------------------------
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
    ok "Toutes les dependances sont presentes."
}

verifier_cles_flux() {
    local ok_flux=true
    if [[ "${CIBLE_PLATEFORME}" =~ ^(dlive|toutes)$ ]] && [[ -z "${DLIVE_CLE_FLUX}" ]]; then
        erreur "Cle de flux DLive manquante (DLIVE_CLE_FLUX dans orbis.conf)"
        ok_flux=false
    fi
    if [[ "${CIBLE_PLATEFORME}" =~ ^(kick|toutes)$ ]] && [[ -z "${KICK_CLE_FLUX}" ]]; then
        erreur "Cle de flux Kick manquante (KICK_CLE_FLUX dans orbis.conf)"
        ok_flux=false
    fi
    [[ "${ok_flux}" == "false" ]] && exit 1
    ok "Cles de flux verifiees."
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
    ok "Liste de lecture chargee : ${LDL_FICHIER} (${nb_entrees} entrees)"
}

# =============================================================================
# verifier_btfs : verifie le daemon BTFS (API port 5001) ET la passerelle
#                 HTTP fichiers (port 8080) -- deux services distincts !
#
# Architecture BTFS :
#   API   http://127.0.0.1:5001/api/v1/...  -> controle du daemon
#   GW    http://127.0.0.1:8080/btfs/<HASH> -> acces aux fichiers
# =============================================================================
verifier_btfs() {
    info "Verification du daemon BTFS..."

    # Etape 1 : daemon actif ? (via CLI locale, sans HTTP)
    if ! command -v btfs &>/dev/null; then
        erreur "Commande btfs introuvable. Consultez docs/BTFS.md"
        exit 1
    fi
    if ! btfs version &>/dev/null 2>&1; then
        avert "Daemon BTFS inactif. Tentative de demarrage..."
        eval "${BTFS_DAEMON_CMD}" &>/dev/null &
        sleep "${BTFS_DELAI_DEMARRAGE}"
        if ! btfs version &>/dev/null 2>&1; then
            erreur "Impossible de demarrer le daemon BTFS."
            erreur "Lancez manuellement : ${BTFS_DAEMON_CMD}"
            exit 1
        fi
    fi
    local version_btfs
    version_btfs=$(btfs version 2>/dev/null | grep -oE "[0-9]+\.[0-9]+\.[0-9]+-?[a-zA-Z0-9]*" | head -1 || echo "?")
    ok "Daemon BTFS actif (v${version_btfs})"

    # Etape 2 : passerelle HTTP fichiers accessible ?
    # IMPORTANT : en BTFS 4.x, / retourne 401 mais /btfs/<HASH> fonctionne.
    # On teste donc directement avec un hash reel (les 512 premiers octets).
    info "Test passerelle HTTP BTFS sur ${BTFS_PASSERELLE}..."
    local url_test="${BTFS_PASSERELLE}/${BTFS_HASH_TEST}"
    local code_http
    code_http=$("${CURL}" -sf --max-time 20 --range "0-511" \
                -o /dev/null -w "%{http_code}" "${url_test}" 2>/dev/null || echo "000")
    case "${code_http}" in
        200|206) ok "Passerelle HTTP BTFS accessible : ${BTFS_PASSERELLE} (HTTP ${code_http})" ;;
        000)     erreur "Passerelle HTTP BTFS muette sur le port ${BTFS_PORT_PASSERELLE}"
                 erreur "  ss -tlnp | grep ${BTFS_PORT_PASSERELLE}"
                 exit 1 ;;
        401)     erreur "Passerelle HTTP BTFS retourne 401 meme sur les fichiers."
                 erreur "  Verifiez la config BTFS : btfs config Addresses.Gateway"
                 exit 1 ;;
        *)       avert "Passerelle HTTP BTFS : code inattendu ${code_http} (on continue)" ;;
    esac
}

# --- Configuration dynamique de nginx-rtmp -----------------------------------
generer_config_nginx() {
    info "Configuration nginx (module RTMP)..."
    local nginx_conf="/etc/nginx/nginx.conf"
    local rtmp_bloc="/etc/nginx/orbis-rtmp-block.conf"
    local stats_conf="/etc/nginx/sites-enabled/orbis-stats.conf"

    # --- 1. Nettoyer les fichiers mal places de sessions precedentes -------
    for f_ancien in "/etc/nginx/sites-enabled/orbis-rtmp.conf" \
                    "/etc/nginx/sites-enabled/orbis-rtmp"; do
        [[ -f "${f_ancien}" ]] && sudo rm -f "${f_ancien}" && \
            info "Ancien fichier supprime : ${f_ancien}"
    done

    # --- 2. Gestion du module RTMP -----------------------------------------
    # Sur Raspberry Pi OS, libnginx-mod-rtmp installe automatiquement
    # /etc/nginx/modules-enabled/50-mod-rtmp.conf (charge via include deja present).
    # load_module dans nginx.conf est une alternative mais DOIT etre en ligne 1.
    # On retire toute tentative precedente ratee (load_module mal positionne).
    if sudo grep -q "load_module.*ngx_rtmp" "${nginx_conf}" 2>/dev/null; then
        local ligne1
        ligne1=$(sudo head -1 "${nginx_conf}")
        if [[ "${ligne1}" =~ load_module.*ngx_rtmp ]]; then
            ok "Module RTMP : load_module deja en ligne 1 de ${nginx_conf}"
        else
            info "Suppression load_module mal positionne dans ${nginx_conf}..."
            sudo sed -i "/.*load_module.*ngx_rtmp_module.*/d" "${nginx_conf}"
            info "load_module supprime (le module sera charge via modules-enabled/)"
        fi
    fi

    # Verifier que le module est bien charge (via modules-enabled/ ou ligne 1)
    local module_ok=false
    if [[ -f /etc/nginx/modules-enabled/50-mod-rtmp.conf ]] || \
       { [[ -f /usr/lib/nginx/modules/ngx_rtmp_module.so ]] && \
         [[ -n "$(ls /etc/nginx/modules-enabled/ 2>/dev/null | grep rtmp)" ]]; }; then
        ok "Module RTMP charge via /etc/nginx/modules-enabled/ (libnginx-mod-rtmp)"
        module_ok=true
    fi

    if [[ "${module_ok}" == "false" ]]; then
        if ! sudo grep -q "^load_module.*ngx_rtmp" "${nginx_conf}"; then
            sudo sed -i "1s|^|load_module modules/ngx_rtmp_module.so;\n|" "${nginx_conf}"
            ok "Module RTMP ajoute en ligne 1 de ${nginx_conf}"
        fi
    fi

    # --- 3. Generer le bloc rtmp {} avec les vraies valeurs ----------------
    {
        echo "# Genere par Orbis Alternis le $(date +'%Y-%m-%d %H:%M:%S')"
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
        if [[ "${DLIVE_ACTIF}" == "true" ]]; then
            echo "            push ${DLIVE_SERVEUR}/${DLIVE_CLE_FLUX};"
        fi
        if [[ "${KICK_ACTIF}" == "true" ]]; then
            echo "            push rtmp://127.0.0.1:${STUNNEL_PORT_LOCAL}/app/${KICK_CLE_FLUX};"
        fi
        echo "        }"
        echo "    }"
        echo "}"
    } | sudo tee "${rtmp_bloc}" > /dev/null
    ok "Bloc RTMP genere : ${rtmp_bloc}"

    # --- 4. Inclure le bloc rtmp en fin de nginx.conf (niveau racine) ------
    if ! sudo grep -q "orbis-rtmp-block.conf" "${nginx_conf}" 2>/dev/null; then
        printf "\n# Orbis Alternis -- bloc RTMP\ninclude %s;\n" "${rtmp_bloc}" \
            | sudo tee -a "${nginx_conf}" > /dev/null
        ok "Include rtmp ajoute dans ${nginx_conf}"
    else
        ok "Include rtmp deja present dans ${nginx_conf}"
    fi

    # --- 5. Serveur HTTP stats (server{} valide dans http{} -> sites-enabled)
    {
        echo "server {"
        echo "    listen 8088;"
        echo "    server_name localhost;"
        echo "    location /stat { rtmp_stat all; rtmp_stat_stylesheet stat.xsl; }"
        echo "    location /controle { rtmp_control all; }"
        echo "}"
    } | sudo tee "${stats_conf}" > /dev/null
    ok "Stats HTTP nginx-rtmp : port 8088"

    # --- 6. Validation et rechargement ------------------------------------
    if ! sudo nginx -t 2>>"${JOURNAL}"; then
        erreur "Configuration nginx invalide."
        erreur "Diagnostic complet : sudo nginx -T 2>&1 | head -50"
        exit 1
    fi
    sudo systemctl reload nginx
    ok "nginx recharge avec la configuration RTMP."
}

# --- Demarrage de Stunnel ----------------------------------------------------
demarrer_stunnel() {
    if [[ "${KICK_ACTIF}" != "true" ]]; then return 0; fi
    info "Demarrage de Stunnel (tunnel RTMPS Kick)..."
    sudo cp "${PROJET_DIR}/conf/stunnel-kick.conf" /etc/stunnel/stunnel.conf
    sudo systemctl restart stunnel4
    sleep 2
    if ! systemctl is-active --quiet stunnel4; then
        erreur "Stunnel n'a pas pu demarrer. Voir /var/log/stunnel4/stunnel.log"
        exit 1
    fi
    ok "Stunnel actif sur le port local ${STUNNEL_PORT_LOCAL} -> Kick RTMPS"
}

# =============================================================================
# ARCHITECTURE FLUX CONTINU (sans coupure entre les videos)
# =============================================================================
#
# Principe : une seule instance FFmpeg tourne en permanence et lit les videos
# via le demuxeur concat de FFmpeg (liste de fichiers/URLs).
#
# Schema :
#
#   [bash: boucle LDL] -- genere --> fichier_concat.txt
#                                           |
#                                           v
#   FFmpeg unique : -f concat -i fichier_concat.txt
#                  -> decode -> filtre -> encode -> RTMP -> nginx -> DLive/Kick
#
# Le flux RTMP n'est JAMAIS coupe entre deux videos. La transition est
# transparente pour les plateformes et les spectateurs.
# =============================================================================

# --- Construction du filtre video --------------------------------------------
# Remplit les variables globales FILTRE_MODE et FILTRE_VALEUR
construire_filtre_video() {
    local base="scale=w=${LARGEUR_MAX}:h=${HAUTEUR_MAX}:force_original_aspect_ratio=decrease,"
    base+="pad=${LARGEUR_MAX}:${HAUTEUR_MAX}:(ow-iw)/2:(oh-ih)/2:black,setsar=1"

    [[ "${OPT_WEBCAM}" == "true" ]] && WEBCAM_FILTRE_ACTIF=true

    if [[ "${OPT_FILIGRANE}" == "true" ]] && [[ -f "${FILIGRANE_IMAGE}" ]]; then
        # movie= ajoute une 2e entree -> doit utiliser -filter_complex
        FILTRE_MODE="fc"
        FILTRE_VALEUR="[0:v]${base}[scaled];"
        FILTRE_VALEUR+="movie=${FILIGRANE_IMAGE},colorchannelmixer=aa=${FILIGRANE_OPACITE}[logo];"
        FILTRE_VALEUR+="[scaled][logo]overlay=${FILIGRANE_POSITION}[vout]"
    else
        FILTRE_MODE="vf"
        FILTRE_VALEUR="${base}"
    fi
}

# --- Generer le fichier de liste de concatenation FFmpeg ---------------------
# Format attendu par le demuxeur concat de FFmpeg :
#   ffconcat version 1.0
#   file 'http://...'
#   option safe 0
#   file 'http://...'
#   option safe 0
generer_fichier_concat() {
    local fichier_out="$1"
    shift
    local url

    {
        echo "ffconcat version 1.0"
        for url in "$@"; do
            echo "file '${url}'"
            echo "option safe 0"
        done
    } > "${fichier_out}"
}

# --- Lancer FFmpeg en flux continu sur la liste de concat --------------------
# Un seul processus FFmpeg lit toutes les videos dans l'ordre et encode
# vers RTMP sans jamais couper le flux.
diffuser_flux_continu() {
    local fichier_concat="$1"
    local bitrate_video
    local bitrate_audio
    local url_rtmp_local
    local fifo_log
    local pid_tee
    local code_retour

    url_rtmp_local="rtmp://127.0.0.1:${NGINX_PORT_RTMP}/${NGINX_CHEMIN_APPLICATION}/orbis"

    case "${CIBLE_PLATEFORME}" in
        dlive)  bitrate_video="${DLIVE_BITRATE_VIDEO}"; bitrate_audio="${DLIVE_BITRATE_AUDIO}" ;;
        kick)   bitrate_video="${KICK_BITRATE_VIDEO}";  bitrate_audio="${KICK_BITRATE_AUDIO}" ;;
        *)      bitrate_video="${KICK_BITRATE_VIDEO}";  bitrate_audio="${KICK_BITRATE_AUDIO}" ;;
    esac

    FILTRE_MODE="vf"
    FILTRE_VALEUR=""
    construire_filtre_video

    info "Encodeur  : ${ENCODEUR_VIDEO} | Filtre : ${FILTRE_MODE}"
    info "Bitrates  : video=${bitrate_video}k audio=${bitrate_audio}k"
    info "Cible RTMP: ${url_rtmp_local}"

    # Construction du tableau de commande FFmpeg
    local -a cmd_ffmpeg
    cmd_ffmpeg=(
        "${FFMPEG}"
        -hide_banner -loglevel warning -stats
        -f concat
        -safe 0
        -protocol_whitelist "file,http,https,tcp,tls,crypto"
        -re
        -fflags +genpts
        -i "${fichier_concat}"
    )

    if [[ "${WEBCAM_FILTRE_ACTIF}" == "true" ]]; then
        cmd_ffmpeg+=(
            -f v4l2
            -framerate "${WEBCAM_DEBIT_IMAGES}"
            -video_size "${WEBCAM_LARGEUR}x${WEBCAM_HAUTEUR}"
            -i "${WEBCAM_PERIPHERIQUE}"
        )
    fi

    if [[ "${FILTRE_MODE}" == "fc" ]]; then
        cmd_ffmpeg+=(-filter_complex "${FILTRE_VALEUR}" -map "[vout]" -map "0:a")
    else
        cmd_ffmpeg+=(-vf "${FILTRE_VALEUR}")
    fi

    cmd_ffmpeg+=(-c:v "${ENCODEUR_VIDEO}")

    if [[ "${ENCODEUR_VIDEO}" == "libx264" ]]; then
        cmd_ffmpeg+=(
            -preset "${PRESET_ENCODAGE}"
            -profile:v "${PROFIL_H264}"
            -level:v "${NIVEAU_H264}"
            -b:v "${bitrate_video}k"
            -maxrate "${bitrate_video}k"
            -bufsize "$((bitrate_video * 2))k"
            -x264-params "nal-hrd=cbr:force-cfr=1"
            -g "${GOP}"
            -keyint_min "${GOP}"
            -sc_threshold 0
        )
    elif [[ "${ENCODEUR_VIDEO}" == "h264_v4l2m2m" ]]; then
        cmd_ffmpeg+=(
            -b:v "${bitrate_video}k"
            -maxrate "${bitrate_video}k"
            -bufsize "$((bitrate_video * 2))k"
            -g "${GOP}"
        )
    fi

    cmd_ffmpeg+=(
        -r "${DEBIT_IMAGES}"
        -c:a aac
        -b:a "${bitrate_audio}k"
        -ar 44100
        -ac 2
        -flvflags no_duration_filesize
        -flush_packets 1
        -f flv "${url_rtmp_local}"
    )

    debug "Commande FFmpeg : ${cmd_ffmpeg[*]}"

    # Afficher la progression en temps reel ET dans le journal via FIFO
    fifo_log="$(mktemp -u /tmp/orbis_ffmpeg_XXXXXX.fifo)"
    mkfifo "${fifo_log}"
    tee -a "${JOURNAL}" < "${fifo_log}" &
    pid_tee=$!

    "${cmd_ffmpeg[@]}" 2>"${fifo_log}" &
    PID_FFMPEG=$!

    code_retour=0
    wait "${PID_FFMPEG}" || code_retour=$?
    PID_FFMPEG=""

    wait "${pid_tee}" 2>/dev/null || true
    rm -f "${fifo_log}"
    echo "" >&2

    return ${code_retour}
}

# --- Chargement de la liste de lecture ---------------------------------------
# Remplit les tableaux globaux LDL_URLS[] et LDL_TITRES[]
lire_liste_lecture() {
    local fichier="$1"
    local ligne
    local url
    local titre

    LDL_URLS=()
    LDL_TITRES=()

    while IFS= read -r ligne; do
        [[ -z "${ligne}" ]] && continue
        [[ "${ligne}" =~ ^[[:space:]]*# ]] && continue
        url="$(echo "${ligne}" | sed 's/[[:space:]]*#.*//' | xargs)"
        titre="$(echo "${ligne}" | grep -oP '(?<=#\s{0,5}).*' | xargs 2>/dev/null || true)"
        [[ -z "${titre}" ]] && titre="$(basename "${url}")"
        if [[ "${url}" =~ ^https?:// ]]; then
            LDL_URLS+=("${url}")
            LDL_TITRES+=("${titre}")
        fi
    done < "${fichier}"

    if [[ "${OPT_MELANGE}" == "true" ]]; then
        info "Melange aleatoire de la liste..."
        local i
        local -a idx_melanges
        local -a urls_tmp
        local -a titres_tmp

        idx_melanges=()
        urls_tmp=()
        titres_tmp=()

        mapfile -t idx_melanges < <(for i in "${!LDL_URLS[@]}"; do echo "$i"; done | shuf)
        for i in "${idx_melanges[@]}"; do
            urls_tmp+=("${LDL_URLS[$i]}")
            titres_tmp+=("${LDL_TITRES[$i]}")
        done
        LDL_URLS=("${urls_tmp[@]}")
        LDL_TITRES=("${titres_tmp[@]}")
    fi
}

# --- Boucle principale (flux continu, sans coupure entre videos) -------------
boucle_principale() {
    local fichier_concat
    local tour
    local continuer
    local total
    local i
    local url
    local code
    local essai
    local diffusion_ok
    local code_ffmpeg

    # Tableaux globaux remplis par lire_liste_lecture()
    declare -g -a LDL_URLS=()
    declare -g -a LDL_TITRES=()

    # Tableaux locaux pour les URLs/titres valides du tour courant
    local -a urls_valides
    local -a titres_valides

    info "============================================================"
    info "  Orbis Alternis -- Demarrage de la diffusion (flux continu)"
    info "  Liste     : $(basename "${LDL_FICHIER}")"
    info "  Plateforme: ${CIBLE_PLATEFORME}"
    info "  Bouclage  : ${OPT_BOUCLE} | Melange : ${OPT_MELANGE}"
    info "============================================================"

    # Fichier de concatenation temporaire (liste des URLs pour FFmpeg concat)
    fichier_concat="$(mktemp /tmp/orbis_concat_XXXXXX.txt)"

    tour=1
    continuer=true

    while [[ "${continuer}" == "true" ]]; do

        # --- Charger et valider la liste ------------------------------------
        lire_liste_lecture "${LDL_FICHIER}"
        total="${#LDL_URLS[@]}"

        if (( total == 0 )); then
            erreur "La liste de lecture est vide. Arret."
            break
        fi

        info "--- Tour ${tour} : ${total} video(s) en flux continu ---"

        for i in "${!LDL_URLS[@]}"; do
            info "  $((i+1))/${total} : ${LDL_TITRES[$i]}"
        done

        # --- Verifier les sources BTFS -------------------------------------
        info "Verification des sources BTFS..."
        urls_valides=()
        titres_valides=()

        for i in "${!LDL_URLS[@]}"; do
            url="${LDL_URLS[$i]}"
            code="$("${CURL}" -sf --max-time 15 --range "0-511" \
                -o /dev/null -w "%{http_code}" "${url}" 2>/dev/null || echo "000")"
            if [[ "${code}" =~ ^2 ]]; then
                urls_valides+=("${url}")
                titres_valides+=("${LDL_TITRES[$i]}")
                debug "  OK (HTTP ${code}) : ${LDL_TITRES[$i]}"
            else
                avert "  IGNOREE (HTTP ${code}) : ${LDL_TITRES[$i]} -- ${url}"
            fi
        done

        if (( ${#urls_valides[@]} == 0 )); then
            erreur "Aucune source valide dans ce tour. Attente ${DELAI_RECONNEXION}s..."
            sleep "${DELAI_RECONNEXION}"
            if [[ "${OPT_BOUCLE}" == "true" ]]; then
                tour=$(( tour + 1 ))
                continue
            else
                break
            fi
        fi

        # --- Generer le fichier concat pour FFmpeg -------------------------
        generer_fichier_concat "${fichier_concat}" "${urls_valides[@]}"
        debug "Fichier concat : $(cat "${fichier_concat}")"

        # --- Lancer FFmpeg en flux continu ---------------------------------
        info "----------------------------------------------------"
        info "Lancement du flux continu (${#urls_valides[@]} video(s))"
        info "----------------------------------------------------"

        essai=1
        diffusion_ok=false
        code_ffmpeg=0

        while (( essai <= TENTATIVES_RECONNEXION )); do
            if diffuser_flux_continu "${fichier_concat}"; then
                diffusion_ok=true
                break
            fi
            code_ffmpeg=$?
            avert "Flux interrompu (essai ${essai}/${TENTATIVES_RECONNEXION}, code ${code_ffmpeg})"
            if (( essai < TENTATIVES_RECONNEXION )); then
                avert "Reprise dans ${DELAI_RECONNEXION}s..."
                sleep "${DELAI_RECONNEXION}"
                generer_fichier_concat "${fichier_concat}" "${urls_valides[@]}"
            fi
            essai=$(( essai + 1 ))
        done

        if [[ "${diffusion_ok}" == "false" ]]; then
            erreur "Echec definitif du flux apres ${TENTATIVES_RECONNEXION} tentatives."
        else
            ok "Tour ${tour} termine (${#urls_valides[@]} video(s) diffusees en flux continu)."
        fi

        # --- Gestion du bouclage -------------------------------------------
        if [[ "${OPT_BOUCLE}" == "true" ]]; then
            tour=$(( tour + 1 ))
            info "Reprise du tour ${tour} dans ${DELAI_ENTRE_VIDEOS}s..."
            sleep "${DELAI_ENTRE_VIDEOS}"
        else
            continuer=false
        fi

    done

    rm -f "${fichier_concat}" 2>/dev/null || true
    info "Diffusion terminee."
}

# --- Point d'entree ----------------------------------------------------------
main() {
    info "Orbis Alternis -- Diffuseur RTMPS/BTFS v1.1 (ARM64)"
    info "Configuration : ${FICHIER_CONF}"
    verifier_dependances
    verifier_cles_flux
    verifier_btfs
    verifier_ldl
    generer_config_nginx
    demarrer_stunnel
    find "${REPERTOIRE_JOURNAUX}" -name "*.log" -mtime "+${CONSERVATION_JOURNAUX}" -delete 2>/dev/null || true
    boucle_principale
}

main "$@"
