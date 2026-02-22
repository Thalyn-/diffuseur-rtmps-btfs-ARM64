# Configuration — Orbis Alternis

Référence complète de tous les paramètres de configuration du projet.

---

## Fichier principal : `conf/orbis.conf`

C'est **l'unique fichier à modifier** pour paramétrer le système.  
Ne jamais committer les clés de flux sur git — utiliser des variables d'environnement ou un fichier `.local` non versionné.

### Paramètres BTFS

| Variable | Défaut | Description |
|----------|--------|-------------|
| `BTFS_PASSERELLE` | `http://127.0.0.1:8080/btfs` | URL de la passerelle HTTP BTFS locale |
| `BTFS_CHAINE_ID` | `1029` | ID de chaîne : `1029` (testnet) ou `199` (mainnet) |
| `BTFS_DELAI_DEMARRAGE` | `10` | Secondes d'attente après démarrage du démon |

### Paramètres d'encodage

| Variable | Défaut | Description |
|----------|--------|-------------|
| `ENCODEUR_VIDEO` | `libx264` | `libx264` (logiciel) ou `h264_v4l2m2m` (matériel Pi4) |
| `PRESET_ENCODAGE` | `veryfast` | Qualité/vitesse : `ultrafast` → `medium` |
| `DEBIT_IMAGES` | `30` | Images par seconde (IPS) |
| `GOP` | `60` | Intervalle d'images-clés (= 2 × IPS recommandé) |
| `LARGEUR_MAX` | `1920` | Largeur maximale en pixels |
| `HAUTEUR_MAX` | `1080` | Hauteur maximale en pixels |

### Choix de l'encodeur

**`libx264` (logiciel)** — Recommandé pour la compatibilité :
```bash
ENCODEUR_VIDEO="libx264"
PRESET_ENCODAGE="veryfast"
```
Charge CPU : ~80-90% sur Pi4 à 1080p/30fps.

**`h264_v4l2m2m` (matériel)** — Recommandé pour les performances :
```bash
ENCODEUR_VIDEO="h264_v4l2m2m"
```
Charge CPU : ~20-30%. Nécessite `/dev/video10` ou `/dev/video11` actif.

### Paramètres DLive

| Variable | Description |
|----------|-------------|
| `DLIVE_ACTIF` | `true`/`false` — Activer la diffusion vers DLive |
| `DLIVE_SERVEUR` | `rtmp://stream.dlive.tv/live` |
| `DLIVE_CLE_FLUX` | **À renseigner** — Clé obtenue sur dlive.tv/settings |
| `DLIVE_BITRATE_VIDEO` | `4500` kbps (max recommandé DLive) |
| `DLIVE_BITRATE_AUDIO` | `160` kbps |

### Paramètres Kick

| Variable | Description |
|----------|-------------|
| `KICK_ACTIF` | `true`/`false` — Activer la diffusion vers Kick |
| `KICK_SERVEUR_REEL` | `fa723fc1b171.global-contribute.live-video.net` |
| `KICK_CLE_FLUX` | **À renseigner** — Clé obtenue sur kick.com/dashboard/stream |
| `KICK_BITRATE_VIDEO` | `6000` kbps (max recommandé Kick) |
| `STUNNEL_PORT_LOCAL` | `11935` — Port local du tunnel Stunnel |

---

## Configuration nginx-rtmp

Le fichier `conf/nginx-rtmp.conf` est un **modèle** — le script `diffuser.sh` le remplit automatiquement avec les valeurs de `orbis.conf`.

### Architecture du flux

```
BTFS HTTP (port 8080)
        │
        ▼
   FFmpeg (encodage H.264/AAC)
        │
        ▼
nginx-rtmp local (port 1935)
   ┌────┴─────┐
   ▼          ▼
DLive       Stunnel local (port 11935)
(RTMP)            │
                  ▼
              Kick.com
             (RTMPS/TLS)
```

### Configuration nginx manuelle

Si vous préférez une configuration nginx fixe (sans régénération automatique) :

```nginx
# /etc/nginx/nginx.conf — ajouter avant le bloc http {}
load_module modules/ngx_rtmp_module.so;

rtmp {
    server {
        listen 1935;
        chunk_size 4096;

        application diffusion {
            live on;
            record off;
            allow publish 127.0.0.1;
            deny publish all;

            push rtmp://stream.dlive.tv/live/VOTRE_CLE_DLIVE;
            push rtmp://127.0.0.1:11935/app/VOTRE_CLE_KICK;
        }
    }
}
```

---

## Configuration Stunnel

Le fichier `conf/stunnel-kick.conf` configure le tunnel TLS vers Kick.

```ini
[kick-rtmps]
client = yes
accept  = 127.0.0.1:11935   # nginx-rtmp pousse ici
connect = fa723fc1b171.global-contribute.live-video.net:443
verify = 2
CAfile = /etc/ssl/certs/ca-certificates.crt
```

Pour appliquer :
```bash
sudo cp conf/stunnel-kick.conf /etc/stunnel/stunnel.conf
sudo systemctl restart stunnel4
```

---

## Gestion du filigrane (logo)

Activer dans `orbis.conf` :
```bash
FILIGRANE_ACTIF=true
FILIGRANE_IMAGE="/home/thalyn/OrbisAlternis/img/logo.png"
FILIGRANE_POSITION="10:10"   # x:y depuis le coin haut-gauche
FILIGRANE_OPACITE=0.85       # 0.0 (transparent) → 1.0 (opaque)
```

Positions prédéfinies recommandées :
- Haut-gauche : `10:10`
- Haut-droite : `main_w-overlay_w-10:10`
- Bas-gauche : `10:main_h-overlay_h-10`
- Bas-droite : `main_w-overlay_w-10:main_h-overlay_h-10`

L'image doit être au format **PNG avec transparence** (canal alpha).

---

## Surcouche webcam (watch party)

Activer dans `orbis.conf` :
```bash
WEBCAM_ACTIF=true
WEBCAM_PERIPHERIQUE="/dev/video0"
WEBCAM_LARGEUR=320
WEBCAM_HAUTEUR=180
WEBCAM_POSITION="main_w-overlay_w-10:main_h-overlay_h-10"
```

Vérifier la disponibilité de la webcam :
```bash
v4l2-ctl --list-devices
ls /dev/video*
```
