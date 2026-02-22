# Diffusion RTMP/RTMPS — DLive et Kick

Guide de configuration de la diffusion vers DLive (RTMP) et Kick (RTMPS).

---

## Récupérer vos clés de flux

### DLive

1. Se connecter sur [dlive.tv](https://dlive.tv)
2. Aller dans **Paramètres → Tableau de bord de diffusion**
3. Copier la **Clé de flux**
4. Renseigner dans `conf/orbis.conf` :
   ```bash
   DLIVE_CLE_FLUX="votre_cle_dlive_ici"
   ```

**Serveur RTMP DLive :** `rtmp://stream.dlive.tv/live`  
**Port :** 1935 (RTMP non chiffré)

### Kick

1. Se connecter sur [kick.com](https://kick.com)
2. Aller dans **Tableau de bord → Paramètres de diffusion**
3. Copier la **Clé de flux (Stream Key)**
4. Renseigner dans `conf/orbis.conf` :
   ```bash
   KICK_CLE_FLUX="votre_cle_kick_ici"
   ```

**Serveur RTMPS Kick :** `fa723fc1b171.global-contribute.live-video.net:443`  
**Port :** 443 (RTMPS chiffré TLS)

---

## Paramètres recommandés par plateforme

### DLive

| Paramètre | Valeur recommandée |
|-----------|-------------------|
| Codec vidéo | H.264 (profil Main, niveau 4.0) |
| Débit vidéo | 2500–4500 kbps |
| Résolution max | 1920×1080 (1080p) |
| Images/seconde | 30 fps |
| Intervalles d'images-clés | 2 secondes (GOP=60) |
| Codec audio | AAC |
| Débit audio | 128–160 kbps |
| Fréquence audio | 44 100 Hz |
| Canaux audio | Stéréo (2 canaux) |

### Kick

| Paramètre | Valeur recommandée |
|-----------|-------------------|
| Codec vidéo | H.264 (profil Main, niveau 4.0) |
| Débit vidéo | 3500–6000 kbps |
| Résolution max | 1920×1080 (1080p) |
| Images/seconde | 30 ou 60 fps |
| Intervalles d'images-clés | 2 secondes (GOP=60) |
| Codec audio | AAC |
| Débit audio | 160 kbps |
| Fréquence audio | 44 100 Hz |
| Protocole | **RTMPS** (TLS obligatoire) |

---

## Architecture technique

```
┌─────────────────────────────────────────────────────────┐
│                   Raspberry Pi 4                        │
│                                                         │
│  BTFS (:8080) → FFmpeg → nginx-rtmp (:1935)            │
│                              │                          │
│                    ┌─────────┴──────────┐               │
│                    │                    │               │
│             RTMP direct          Stunnel (:11935)       │
│                    │                    │               │
└────────────────────┼────────────────────┼───────────────┘
                     │                    │ TLS
                     ▼                    ▼
              dlive.tv:1935     fa723fc1b171...:443
              (DLive RTMP)      (Kick RTMPS)
```

---

## Pourquoi Stunnel pour Kick ?

Kick exige le protocole **RTMPS** (RTMP chiffré via TLS/SSL), contrairement à DLive qui accepte du RTMP non chiffré.

Stunnel crée un **tunnel transparent** :
- nginx-rtmp envoie du RTMP classique vers `localhost:11935`
- Stunnel encapsule ce RTMP dans une connexion TLS
- Kick reçoit du RTMPS valide sur le port 443

> **Alternative :** Si votre version de FFmpeg supporte `rtmps://` nativement (compilée avec OpenSSL), vous pouvez envoyer directement vers Kick sans Stunnel. Vérifier avec :
> ```bash
> ffmpeg -protocols 2>/dev/null | grep rtmps
> ```

---

## Diffusion vers une seule plateforme

```bash
# DLive uniquement
./scripts/diffuser.sh -p dlive

# Kick uniquement
./scripts/diffuser.sh -p kick
```

## Diffusion simultanée (multi-plateforme)

```bash
# Les deux plateformes (par défaut)
./scripts/diffuser.sh -p toutes
```

En mode multi-plateforme, nginx-rtmp reçoit le flux encodé une seule fois et le distribue simultanément. La charge CPU du Pi4 reste identique qu'il y ait une ou deux destinations.

---

## Gestion des interruptions et reconnexions

Si la connexion vers une plateforme est interrompue :
- **nginx-rtmp** tente automatiquement de se reconnecter (paramètre `TENTATIVES_RECONNEXION`)
- Le flux vers l'autre plateforme continue sans interruption
- Les journaux indiquent les erreurs de connexion

Pour forcer une reconnexion manuelle :
```bash
sudo systemctl reload nginx
```

---

## Vérification du flux en production

### Consulter les statistiques nginx-rtmp

Ouvrir dans un navigateur (depuis le Pi) :
```
http://127.0.0.1:8088/stat
```

### Tester la connexion Stunnel → Kick

```bash
# Vérifier que Stunnel écoute sur le port local
ss -tlnp | grep 11935

# Test de connexion TLS
openssl s_client -connect fa723fc1b171.global-contribute.live-video.net:443 -brief
```

### Tester FFmpeg seul (sans diffusion réelle)

```bash
ffmpeg -re -i "http://127.0.0.1:8080/btfs/QmbQb1kfwEmf4sqCUcccDYHBiuvKAsE4h8LQsQJ13VvZR2" \
  -t 10 \
  -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:black" \
  -c:v libx264 -preset veryfast -b:v 4500k \
  -c:a aac -b:a 160k \
  -f null /dev/null
```
