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

nettoyer() {
    info "Signal recu -- arret propre en cours..."
    [[ -n "${PID_FFMPEG}" ]] && kill -SIGTERM "${PID_FFMPEG}" 2>/dev/null && wait "${PID_FFMPEG}" 2>/dev/null || true
    if [[ -f "${PROJET_DIR}/conf/nginx-rtmp.conf.bak" ]]; then
        sudo mv "${PROJET_DIR}/conf/nginx-rtmp.conf.bak" "${PROJET_DIR}/conf/nginx-rtmp.conf" 2>/dev/null || true
        sudo systemctl reload nginx 2>/dev/null || true
    fi
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
        [[ ! -x "${outil}" ]] && manquants+=("")
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

    # --- 1. Supprimer l ancien fichier mal place (sites-enabled ne peut pas
    #        contenir de blocs rtmp/events/load_module = niveau racine nginx)
    for f_mauvais in "/etc/nginx/sites-enabled/orbis-rtmp.conf" \
                    "/etc/nginx/sites-enabled/orbis-rtmp"; do
        [[ -f "${f_mauvais}" ]] && sudo rm -f "${f_mauvais}" && \
            info "Suppression de l ancien fichier mal place : ${f_mauvais}"
    done

    # --- 2. Activer load_module ngx_rtmp dans nginx.conf -------------------
    if sudo grep -q "^load_module.*ngx_rtmp" "${nginx_conf}" 2>/dev/null; then
        ok "Module RTMP deja actif dans ${nginx_conf}"
    elif sudo grep -q "ngx_rtmp" "${nginx_conf}" 2>/dev/null; then
        # Ligne presente mais commentee -> decommenter
        sudo sed -i \
            "s|^[[:space:]]*#.*load_module.*ngx_rtmp_module.*|load_module modules/ngx_rtmp_module.so;|" \
            "${nginx_conf}"
        ok "Module RTMP active (decommente) dans ${nginx_conf}"
    else
        # Absent -> ajouter en premiere ligne
        sudo sed -i "1s|^|load_module modules/ngx_rtmp_module.so;\n|" "${nginx_conf}"
        ok "Module RTMP ajoute en tete de ${nginx_conf}"
    fi

    # --- 3. Generer le bloc rtmp {} avec les vraies valeurs ----------------
    # (pas de template sed : on ecrit directement avec echo)
    {
        echo "# Genere par Orbis Alternis le $(date +"%Y-%m-%d %H:%M:%S")"
        echo "# Ne pas editer -- relancer diffuser.sh pour mettre a jour"
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

    # --- 4. Inclure le bloc rtmp dans nginx.conf (apres http {}, au niveau racine)
    if ! sudo grep -q "orbis-rtmp-block.conf" "${nginx_conf}" 2>/dev/null; then
        echo "" | sudo tee -a "${nginx_conf}" > /dev/null
        echo "# Orbis Alternis -- bloc RTMP (inclus au niveau racine, hors http {})" \
            | sudo tee -a "${nginx_conf}" > /dev/null
        echo "include ${rtmp_bloc};" | sudo tee -a "${nginx_conf}" > /dev/null
        ok "Include rtmp ajoute dans ${nginx_conf} (apres http {})"
    else
        ok "Include rtmp deja present dans ${nginx_conf}"
    fi

    # --- 5. Serveur HTTP stats (dans sites-enabled, a l interieur de http {})
    {
        echo "# Stats nginx-rtmp -- Orbis Alternis"
        echo "server {"
        echo "    listen 8088;"
        echo "    server_name localhost;"
        echo "    location /stat {"
        echo "        rtmp_stat all;"
        echo "        rtmp_stat_stylesheet stat.xsl;"
        echo "    }"
        echo "    location /controle {"
        echo "        rtmp_control all;"
        echo "    }"
        echo "}"
    } | sudo tee "${stats_conf}" > /dev/null
    ok "Stats HTTP nginx-rtmp configurees : ${stats_conf}"

    # --- 6. Validation et rechargement -------------------------------------
    if ! sudo nginx -t 2>>"${JOURNAL}"; then
        erreur "Configuration nginx invalide."
        erreur "Verifiez : sudo nginx -T 2>&1 | head -40"
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

# --- Construction des filtres video FFmpeg -----------------------------------
construire_filtre_video() {
    local vf="scale=w=${LARGEUR_MAX}:h=${HAUTEUR_MAX}:force_original_aspect_ratio=decrease,"
    vf+="pad=${LARGEUR_MAX}:${HAUTEUR_MAX}:(ow-iw)/2:(oh-ih)/2:black"

    if [[ "${OPT_FILIGRANE}" == "true" ]] && [[ -f "${FILIGRANE_IMAGE}" ]]; then
        vf+=",movie=${FILIGRANE_IMAGE},colorchannelmixer=aa=${FILIGRANE_OPACITE}[logo]"
        vf+=";[in][logo]overlay=${FILIGRANE_POSITION}[out]"
    fi
    [[ "${OPT_WEBCAM}" == "true" ]] && WEBCAM_FILTRE_ACTIF=true
    echo "${vf}"
}

# --- Construction et lancement de la commande FFmpeg -------------------------
diffuser_video() {
    local url_source="$1"
    local titre="${2:-inconnu}"
    local bitrate_video bitrate_audio
    local url_rtmp_local="rtmp://127.0.0.1:${NGINX_PORT_RTMP}/${NGINX_CHEMIN_APPLICATION}/orbis"

    case "${CIBLE_PLATEFORME}" in
        dlive)  bitrate_video="${DLIVE_BITRATE_VIDEO}"; bitrate_audio="${DLIVE_BITRATE_AUDIO}" ;;
        kick)   bitrate_video="${KICK_BITRATE_VIDEO}";  bitrate_audio="${KICK_BITRATE_AUDIO}" ;;
        *)      bitrate_video="${KICK_BITRATE_VIDEO}";  bitrate_audio="${KICK_BITRATE_AUDIO}" ;;
    esac

    local filtre_video
    filtre_video="$(construire_filtre_video)"

    info "----------------------------------------------------"
    info "Diffusion : ${titre}"
    info "Source    : ${url_source}"
    info "Cible     : ${CIBLE_PLATEFORME} | Video : ${bitrate_video}k | Audio : ${bitrate_audio}k"
    info "----------------------------------------------------"

    # FFmpeg lit directement depuis la passerelle HTTP BTFS.
    # Note : en BTFS 4.x, /btfs/<HASH> fonctionne sans auth
    # (seul le chemin racine / retourne 401).
    local cmd_ffmpeg=(
        "${FFMPEG}"
        -hide_banner -loglevel warning -stats
        -re
        -i "${url_source}"
    )

    if [[ "${WEBCAM_FILTRE_ACTIF}" == "true" ]]; then
        cmd_ffmpeg+=(
            -f v4l2
            -framerate "${WEBCAM_DEBIT_IMAGES}"
            -video_size "${WEBCAM_LARGEUR}x${WEBCAM_HAUTEUR}"
            -i "${WEBCAM_PERIPHERIQUE}"
        )
    fi

    cmd_ffmpeg+=(-vf "${filtre_video}" -c:v "${ENCODEUR_VIDEO}")

    if [[ "${ENCODEUR_VIDEO}" == "libx264" ]]; then
        cmd_ffmpeg+=(
            -preset "${PRESET_ENCODAGE}"
            -profile:v "${PROFIL_H264}" -level:v "${NIVEAU_H264}"
            -b:v "${bitrate_video}k" -maxrate "${bitrate_video}k"
            -bufsize "$((bitrate_video * 2))k"
            -x264-params "nal-hrd=cbr:force-cfr=1"
        )
    elif [[ "${ENCODEUR_VIDEO}" == "h264_v4l2m2m" ]]; then
        cmd_ffmpeg+=(
            -b:v "${bitrate_video}k" -maxrate "${bitrate_video}k"
            -bufsize "$((bitrate_video * 2))k"
            -num_capture_buffers 64
        )
    fi

    cmd_ffmpeg+=(
        -g "${GOP}" -keyint_min "${GOP}" -sc_threshold 0 -r "${DEBIT_IMAGES}"
        -c:a aac -b:a "${bitrate_audio}k" -ar 44100 -ac 2
        -f flv "${url_rtmp_local}"
    )

    debug "Commande FFmpeg : ${cmd_ffmpeg[*]}"

    "${cmd_ffmpeg[@]}" 2>>"${JOURNAL}" &
    PID_FFMPEG=$!
    local code_retour=0
    wait "${PID_FFMPEG}" || code_retour=$?
    PID_FFMPEG=""

    if (( code_retour == 0 )); then
        ok "Video terminee : ${titre}"
    else
        avert "FFmpeg code ${code_retour} pour : ${titre}"
    fi
    return ${code_retour}
}

# --- Chargement de la liste de lecture ---------------------------------------
lire_liste_lecture() {
    local fichier="$1"
    local -a urls=() titres=()

    while IFS= read -r ligne; do
        [[ -z "${ligne}" ]] && continue
        [[ "${ligne}" =~ ^[[:space:]]*# ]] && continue
        local url titre
        url="$(echo "${ligne}" | sed 's/[[:space:]]*#.*//' | xargs)"
        titre="$(echo "${ligne}" | grep -oP '(?<=#\s?).*' | xargs 2>/dev/null || echo "Sans titre")"
        [[ -z "${titre}" ]] && titre="$(basename "${url}")"
        if [[ "${url}" =~ ^https?:// ]]; then
            urls+=("${url}"); titres+=("${titre}")
        fi
    done < "${fichier}"

    if [[ "${OPT_MELANGE}" == "true" ]]; then
        info "Melange aleatoire de la liste..."
        local -a idx_melanges
        mapfile -t idx_melanges < <(for i in "${!urls[@]}"; do echo "$i"; done | shuf)
        local -a urls_tmp=() titres_tmp=()
        for i in "${idx_melanges[@]}"; do
            urls_tmp+=("${urls[$i]}")
            titres_tmp+=("${titres[$i]}")
        done
        urls=("${urls_tmp[@]}"); titres=("${titres_tmp[@]}")
    fi

    local tmp_urls tmp_titres
    tmp_urls="$(mktemp)"; tmp_titres="$(mktemp)"
    printf '%s\n' "${urls[@]}" > "${tmp_urls}"
    printf '%s\n' "${titres[@]}" > "${tmp_titres}"
    echo "${tmp_urls}:${tmp_titres}"
}

# --- Boucle principale -------------------------------------------------------
boucle_principale() {
    info "============================================================"
    info "  Orbis Alternis -- Demarrage de la diffusion"
    info "  Liste     : $(basename "${LDL_FICHIER}")"
    info "  Plateforme: ${CIBLE_PLATEFORME}"
    info "  Bouclage  : ${OPT_BOUCLE} | Melange : ${OPT_MELANGE}"
    info "============================================================"

    local tour=1 continuer=true

    while [[ "${continuer}" == "true" ]]; do
        info "--- Tour n${tour} de la liste de lecture ---"

        local fichiers_tmp
        fichiers_tmp="$(lire_liste_lecture "${LDL_FICHIER}")"
        local tmp_urls="${fichiers_tmp%%:*}"
        local tmp_titres="${fichiers_tmp##*:}"
        local index=0 total
        total="$(wc -l < "${tmp_urls}")"

        while IFS= read -r url && IFS= read -r titre <&3; do
            index=$(( index + 1 ))
            info "[${index}/${total}] Preparation : ${titre}"

            local tentative=1 source_ok=false
            while (( tentative <= TENTATIVES_RECONNEXION )); do
                # Tester les 512 premiers octets de l URL HTTP BTFS (pas HEAD car BTFS repond mieux a GET)
                if "${CURL}" -sf --max-time 20 --range "0-511" -o /dev/null "${url}" 2>/dev/null; then
                    source_ok=true; break
                fi
                avert "Source inaccessible (tentative ${tentative}/${TENTATIVES_RECONNEXION}) : ${url}"
                sleep "${DELAI_RECONNEXION}"
                tentative=$(( tentative + 1 ))
            done

            if [[ "${source_ok}" == "false" ]]; then
                erreur "Source inaccessible apres ${TENTATIVES_RECONNEXION} tentatives. Passage a la suivante."
                continue
            fi

            local essai=1 diffusion_ok=false
            while (( essai <= TENTATIVES_RECONNEXION )); do
                if diffuser_video "${url}" "${titre}"; then
                    diffusion_ok=true; break
                fi
                avert "Erreur diffusion (essai ${essai}/${TENTATIVES_RECONNEXION}). Reprise dans ${DELAI_RECONNEXION}s..."
                sleep "${DELAI_RECONNEXION}"
                essai=$(( essai + 1 ))
            done

            [[ "${diffusion_ok}" == "false" ]] && erreur "Echec definitif pour : ${titre}"
            (( index < total )) && sleep "${DELAI_ENTRE_VIDEOS}"

        done < "${tmp_urls}" 3< "${tmp_titres}"
        rm -f "${tmp_urls}" "${tmp_titres}"

        if [[ "${OPT_BOUCLE}" == "true" ]]; then
            tour=$(( tour + 1 ))
            sleep "${DELAI_ENTRE_VIDEOS}"
        else
            continuer=false
        fi
    done
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
