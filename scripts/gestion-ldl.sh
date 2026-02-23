#!/usr/bin/env bash
# =============================================================================
# gestion-ldl.sh — Gestion des listes de lecture (Listes De Lecture)
# =============================================================================
# Usage : ./gestion-ldl.sh <COMMANDE> [OPTIONS]
#
# Commandes disponibles :
#   lister                     Afficher toutes les listes de lecture
#   afficher <ldl>             Afficher le contenu d'une liste
#   ajouter  <ldl> <url> [titre]   Ajouter une entrée BTFS à une liste
#   supprimer <ldl> <url>      Supprimer une entrée d'une liste
#   creer    <ldl> [description]   Créer une nouvelle liste thématique
#   verifier <ldl>             Vérifier l'accessibilité de toutes les sources
#   stats    [ldl]             Statistiques (nombre d'entrées, taille...)
#   deduplication <ldl>        Supprimer les doublons d'une liste
#   exporter <ldl> <format>    Exporter la liste (txt|m3u|json)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJET_DIR="$(dirname "${SCRIPT_DIR}")"
source "${PROJET_DIR}/conf/orbis.conf"

# --- Journalisation légère ---------------------------------------------------
_log() { printf "[%s] [%-6s] %s\n" "$(date +'%H:%M:%S')" "$1" "$2"; }
info()   { _log "INFO"  "$1"; }
ok()     { _log "OK"    "$1"; }
avert()  { _log "AVERT" "$1"; }
erreur() { _log "ERREUR" "$1" >&2; }

# --- Résolution du nom de liste ----------------------------------------------
# Accepte : ldl_dystopies | ldl_dystopies.txt | dystopies
resoudre_ldl() {
    local nom="$1"
    local chemin

    # Si c'est déjà un chemin absolu ou relatif existant
    if [[ -f "${nom}" ]]; then
        echo "${nom}"; return
    fi
    # Avec préfixe ldl_ et extension
    chemin="${REPERTOIRE_LDL}/${nom}"
    [[ -f "${chemin}" ]] && { echo "${chemin}"; return; }
    chemin="${REPERTOIRE_LDL}/${nom}.txt"
    [[ -f "${chemin}" ]] && { echo "${chemin}"; return; }
    chemin="${REPERTOIRE_LDL}/ldl_${nom}.txt"
    [[ -f "${chemin}" ]] && { echo "${chemin}"; return; }

    erreur "Liste de lecture introuvable : ${nom}"
    erreur "Listes disponibles :"
    ls "${REPERTOIRE_LDL}"/ldl_*.txt 2>/dev/null | sed "s|${REPERTOIRE_LDL}/||" >&2 || true
    exit 1
}

# --- COMMANDE : lister -------------------------------------------------------
cmd_lister() {
    info "Listes de lecture disponibles dans ${REPERTOIRE_LDL} :"
    printf "\n%-35s %8s  %s\n" "Nom du fichier" "Entrées" "Description"
    printf "%-35s %8s  %s\n" "$(printf '%.0s-' {1..35})" "-------" "-----------"
    for fichier in "${REPERTOIRE_LDL}"/ldl_*.txt; do
        [[ -f "${fichier}" ]] || continue
        local nom_court description nb_entrees
        nom_court="$(basename "${fichier}")"
        nb_entrees=$(grep -cE '^https?://' "${fichier}" 2>/dev/null || echo 0)
        description=$(grep -m1 '^# Description:' "${fichier}" | sed 's/^# Description:[[:space:]]*//' || echo "—")
        printf "%-35s %8s  %s\n" "${nom_court}" "${nb_entrees}" "${description}"
    done
    echo ""
}

# --- COMMANDE : afficher -----------------------------------------------------
cmd_afficher() {
    local ldl_fichier
    ldl_fichier="$(resoudre_ldl "${1}")"
    info "Contenu de : $(basename "${ldl_fichier}")"
    printf "\n%4s  %-65s  %s\n" "N°" "URL BTFS" "Titre"
    printf "%4s  %-65s  %s\n" "----" "$(printf '%.0s-' {1..65})" "-----"
    local i=0
    while IFS= read -r ligne; do
        [[ -z "${ligne}" ]] && continue
        [[ "${ligne}" =~ ^[[:space:]]*# ]] && continue
        local url titre
        url="$(echo "${ligne}" | sed 's/[[:space:]]*#.*//' | xargs)"
        titre="$(echo "${ligne}" | grep -oP '(?<=#\s?).*' | xargs 2>/dev/null || echo "—")"
        [[ -z "${titre}" ]] && titre="—"
        i=$(( i + 1 ))
        printf "%4d  %-65s  %s\n" "${i}" "${url}" "${titre}"
    done < "${ldl_fichier}"
    echo ""
    info "Total : ${i} entrée(s)"
}

# --- COMMANDE : ajouter ------------------------------------------------------
cmd_ajouter() {
    local ldl_nom="$1"
    local url="$2"
    local titre="${3:-}"
    local ldl_fichier="${REPERTOIRE_LDL}/${ldl_nom}"

    # Normaliser le nom du fichier
    [[ "${ldl_fichier}" != *.txt ]] && ldl_fichier="${ldl_fichier}.txt"
    [[ "$(basename "${ldl_fichier}")" != ldl_* ]] && \
        ldl_fichier="${REPERTOIRE_LDL}/ldl_$(basename "${ldl_fichier}")"

    # Créer la liste si elle n'existe pas encore
    if [[ ! -f "${ldl_fichier}" ]]; then
        avert "La liste n'existe pas. Création automatique : $(basename "${ldl_fichier}")"
        cmd_creer "$(basename "${ldl_fichier}" .txt | sed 's/^ldl_//')"
    fi

    # Vérifier l'URL
    if [[ ! "${url}" =~ ^https?:// ]]; then
        # Peut-être un hash BTFS brut ?
        if [[ "${url}" =~ ^Qm[a-zA-Z0-9]{44}$ ]] || [[ "${url}" =~ ^baf[a-zA-Z0-9]+$ ]]; then
            url="${BTFS_PASSERELLE}/${url}"
            info "Hash BTFS détecté, URL complète : ${url}"
        else
            erreur "URL invalide : ${url}"
            erreur "Format attendu : http://127.0.0.1:8080/btfs/<HASH> ou <HASH_BTFS>"
            exit 1
        fi
    fi

    # Vérifier les doublons
    if grep -qF "${url}" "${ldl_fichier}" 2>/dev/null; then
        avert "Cette URL est déjà présente dans la liste."
        exit 0
    fi

    # Ajouter l'entrée
    if [[ -n "${titre}" ]]; then
        echo "${url}  # ${titre}" >> "${ldl_fichier}"
    else
        echo "${url}" >> "${ldl_fichier}"
    fi

    ok "Ajouté dans $(basename "${ldl_fichier}") : ${url}${titre:+  # ${titre}}"
}

# --- COMMANDE : supprimer ----------------------------------------------------
cmd_supprimer() {
    local ldl_fichier
    ldl_fichier="$(resoudre_ldl "${1}")"
    local url="$2"

    if ! grep -qF "${url}" "${ldl_fichier}"; then
        avert "URL non trouvée dans la liste : ${url}"
        exit 0
    fi

    # Sauvegarde avant modification
    cp "${ldl_fichier}" "${ldl_fichier}.bak"
    grep -vF "${url}" "${ldl_fichier}.bak" > "${ldl_fichier}"
    rm -f "${ldl_fichier}.bak"
    ok "Supprimé de $(basename "${ldl_fichier}") : ${url}"
}

# --- COMMANDE : creer --------------------------------------------------------
cmd_creer() {
    local thematique="$1"
    local description="${2:-Liste thématique ${thematique}}"
    local nom_fichier="${REPERTOIRE_LDL}/ldl_${thematique}.txt"

    if [[ -f "${nom_fichier}" ]]; then
        avert "Cette liste existe déjà : ${nom_fichier}"
        exit 0
    fi

    cat > "${nom_fichier}" << ENTETE
# =============================================================================
# Liste de lecture : ${thematique}
# Description: ${description}
# Créée le : $(date +'%d/%m/%Y')
# Projet : Orbis Alternis — diffuseur-rtmps-btfs-ARM64
# =============================================================================
# Format : URL_BTFS  # Titre du film (Réalisateur, Année)
# Exemple :
#   http://127.0.0.1:8080/btfs/QmXXXXXXXXX  # 2001: L'Odyssée de l'espace (Kubrick, 1968)
# =============================================================================

ENTETE

    ok "Liste créée : ${nom_fichier}"
}

# --- COMMANDE : verifier -----------------------------------------------------
cmd_verifier() {
    local ldl_fichier
    ldl_fichier="$(resoudre_ldl "${1}")"
    info "Vérification de l'accessibilité des sources : $(basename "${ldl_fichier}")"

    local total=0 accessibles=0 inaccessibles=0
    while IFS= read -r ligne; do
        [[ -z "${ligne}" ]] && continue
        [[ "${ligne}" =~ ^[[:space:]]*# ]] && continue
        local url
        url="$(echo "${ligne}" | sed 's/[[:space:]]*#.*//' | xargs)"
        [[ -z "${url}" ]] && continue
        total=$(( total + 1 ))

        printf "  [%3d] Vérification : %s ... " "${total}" "$(basename "${url}")"
        if "${CURL}" -sf --max-time 20 --head "${url}" &>/dev/null; then
            echo "✓ OK"
            accessibles=$(( accessibles + 1 ))
        else
            echo "✗ INACCESSIBLE"
            inaccessibles=$(( inaccessibles + 1 ))
        fi
    done < "${ldl_fichier}"

    echo ""
    info "Résultat : ${accessibles}/${total} sources accessibles, ${inaccessibles} inaccessible(s)"
    (( inaccessibles > 0 )) && avert "Vérifiez que le démon BTFS est en cours d'exécution."
}

# --- COMMANDE : stats --------------------------------------------------------
cmd_stats() {
    local cible="${1:-}"
    local -a fichiers=()

    if [[ -n "${cible}" ]]; then
        fichiers=("$(resoudre_ldl "${cible}")")
    else
        mapfile -t fichiers < <(ls "${REPERTOIRE_LDL}"/ldl_*.txt 2>/dev/null)
    fi

    info "Statistiques des listes de lecture :"
    local total_global=0
    for f in "${fichiers[@]}"; do
        [[ -f "${f}" ]] || continue
        local nb
        nb=$(grep -cE '^https?://' "${f}" 2>/dev/null || echo 0)
        total_global=$(( total_global + nb ))
        printf "  %-40s : %4d entrée(s)\n" "$(basename "${f}")" "${nb}"
    done
    printf "\n  %-40s : %4d entrée(s) au total\n" "TOTAL" "${total_global}"
}

# --- COMMANDE : deduplication ------------------------------------------------
cmd_deduplication() {
    local ldl_fichier
    ldl_fichier="$(resoudre_ldl "${1}")"
    local avant apres
    avant=$(wc -l < "${ldl_fichier}")

    cp "${ldl_fichier}" "${ldl_fichier}.bak"
    # Conserver les commentaires et supprimer les doublons d'URL
    awk '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { print; next }
        { url = $1; if (!seen[url]++) print }
    ' "${ldl_fichier}.bak" > "${ldl_fichier}"
    rm -f "${ldl_fichier}.bak"

    apres=$(wc -l < "${ldl_fichier}")
    local supprimes=$(( avant - apres ))
    ok "Dédoublonnage terminé : ${supprimes} doublon(s) supprimé(s)"
}

# --- COMMANDE : exporter -----------------------------------------------------
cmd_exporter() {
    local ldl_fichier
    ldl_fichier="$(resoudre_ldl "${1}")"
    local format="${2:-txt}"
    local nom_base
    nom_base="$(basename "${ldl_fichier}" .txt)"
    local fichier_sortie="${REPERTOIRE_LDL}/${nom_base}_export.${format}"

    case "${format}" in
        txt)
            cp "${ldl_fichier}" "${fichier_sortie}"
            ;;
        m3u)
            echo "#EXTM3U" > "${fichier_sortie}"
            while IFS= read -r ligne; do
                [[ -z "${ligne}" ]] && continue
                [[ "${ligne}" =~ ^[[:space:]]*# ]] && continue
                local url titre
                url="$(echo "${ligne}" | sed 's/[[:space:]]*#.*//' | xargs)"
                titre="$(echo "${ligne}" | grep -oP '(?<=#\s?).*' | xargs 2>/dev/null || echo "Sans titre")"
                echo "#EXTINF:-1,${titre}" >> "${fichier_sortie}"
                echo "${url}" >> "${fichier_sortie}"
            done < "${ldl_fichier}"
            ;;
        json)
            echo "[" > "${fichier_sortie}"
            local premier=true
            while IFS= read -r ligne; do
                [[ -z "${ligne}" ]] && continue
                [[ "${ligne}" =~ ^[[:space:]]*# ]] && continue
                local url titre
                url="$(echo "${ligne}" | sed 's/[[:space:]]*#.*//' | xargs)"
                titre="$(echo "${ligne}" | grep -oP '(?<=#\s?).*' | xargs 2>/dev/null || echo "Sans titre")"
                [[ "${premier}" == "false" ]] && echo "," >> "${fichier_sortie}"
                printf '  {"url": "%s", "titre": "%s"}' "${url}" "${titre}" >> "${fichier_sortie}"
                premier=false
            done < "${ldl_fichier}"
            echo -e "\n]" >> "${fichier_sortie}"
            ;;
        *)
            erreur "Format inconnu : ${format}. Formats supportés : txt, m3u, json"
            exit 1
            ;;
    esac

    ok "Exporté vers : ${fichier_sortie}"
}

# --- Point d'entrée ----------------------------------------------------------
usage() {
    grep '^#' "${BASH_SOURCE[0]}" | grep -A30 'Commandes' | sed 's/^# \?//'
    exit 0
}

[[ $# -eq 0 ]] && { usage; }

COMMANDE="$1"; shift

case "${COMMANDE}" in
    lister)                      cmd_lister ;;
    afficher|voir|show)          cmd_afficher "${1:-}" ;;
    ajouter|add)                 cmd_ajouter "${1:-}" "${2:-}" "${3:-}" ;;
    supprimer|del|remove)        cmd_supprimer "${1:-}" "${2:-}" ;;
    creer|new|nouveau)           cmd_creer "${1:-}" "${2:-}" ;;
    verifier|check|vérifier)     cmd_verifier "${1:-}" ;;
    stats|statistiques)          cmd_stats "${1:-}" ;;
    deduplication|dedup)         cmd_deduplication "${1:-}" ;;
    exporter|export)             cmd_exporter "${1:-}" "${2:-txt}" ;;
    aide|help|-h|--aide)         usage ;;
    *) erreur "Commande inconnue : ${COMMANDE}"; usage ;;
esac
