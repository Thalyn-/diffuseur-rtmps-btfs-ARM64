# Installation — Orbis Alternis

Guide d'installation complet sur **Raspberry Pi 4** (ARM64, Raspberry Pi OS Bookworm 64 bits).

---

## Prérequis matériel

| Composant | Minimum | Recommandé |
|-----------|---------|------------|
| Modèle | Raspberry Pi 4 | Raspberry Pi 4 (4 Go RAM) |
| Stockage | Carte microSD 32 Go | SSD USB 3.0 64 Go+ |
| Connexion | Ethernet 100 Mbps | Ethernet Gigabit |
| Débit upload | 6 Mbps | 12 Mbps (multi-plateforme) |

---

## 1. Mise à jour du système

```bash
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

---

## 2. Installation des dépendances

```bash
# FFmpeg, cURL, outils réseau
sudo apt install -y ffmpeg curl wget git

# Nginx + module RTMP
sudo apt install -y nginx libnginx-mod-rtmp

# Stunnel (chiffrement TLS pour Kick)
sudo apt install -y stunnel4

# Outils de diagnostic (optionnels mais utiles)
sudo apt install -y htop iotop net-tools
```

### Vérification de FFmpeg ARM64

```bash
ffmpeg -version
# Vérifier la présence de : libx264, aac
ffmpeg -encoders | grep -E 'h264|aac'

# Vérifier l'encodeur matériel du Pi4
v4l2-ctl --list-devices 2>/dev/null | grep -A2 "H.264"
# ou
ls /dev/video*
```

---

## 3. Installation de BTFS

BTFS (BitTorrent File System) version 4.1.0+ pour ARM64 :

```bash
# Télécharger la dernière version ARM64
wget https://github.com/bittorrent/go-btfs/releases/latest/download/btfs-linux-arm64.tar.gz
tar xzf btfs-linux-arm64.tar.gz
sudo mv btfs /usr/local/bin/
sudo chmod +x /usr/local/bin/btfs

# Vérification
btfs version
```

### Initialisation de BTFS

```bash
# Premier lancement (initialise le dépôt dans ~/.btfs)
btfs init

# Démarrage sur le testnet BTTC
btfs daemon --chain-id 1029
# → Laisser tourner en arrière-plan ou créer un service systemd
```

### Service systemd pour BTFS (démarrage automatique)

```bash
sudo tee /etc/systemd/system/btfs.service << 'EOF'
[Unit]
Description=BTFS — Démon BitTorrent File System
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=thalyn
ExecStart=/usr/local/bin/btfs daemon --chain-id 1029
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable btfs
sudo systemctl start btfs

# Vérification
sudo systemctl status btfs
```

---

## 4. Clonage du projet

```bash
cd /home/thalyn
git clone https://github.com/Thalyn-/diffuseur-rtmps-btfs-ARM64.git OrbisAlternis
cd OrbisAlternis
```

### Rendre les scripts exécutables

```bash
chmod +x scripts/*.sh
```

---

## 5. Configuration initiale

```bash
# Copier et éditer la configuration (ne JAMAIS committer vos clés !)
cp conf/orbis.conf conf/orbis.conf.local  # optionnel : config locale non versionnée
nano conf/orbis.conf
```

Renseigner **obligatoirement** :
- `DLIVE_CLE_FLUX` — votre clé de flux DLive
- `KICK_CLE_FLUX` — votre clé de flux Kick

---

## 6. Configuration de Stunnel

```bash
# Copier la configuration Stunnel
sudo cp conf/stunnel-kick.conf /etc/stunnel/stunnel.conf

# Activer Stunnel au démarrage
sudo systemctl enable stunnel4
sudo systemctl start stunnel4
```

---

## 7. Configuration de Nginx

```bash
# Activer le module RTMP dans nginx
# Sur Raspberry Pi OS Bookworm, ajouter dans /etc/nginx/nginx.conf :
# load_module modules/ngx_rtmp_module.so;

# Le script diffuser.sh génère automatiquement la config nginx.
# Pour une configuration manuelle :
sudo nano /etc/nginx/nginx.conf
```

Voir [CONFIGURATION.md](CONFIGURATION.md) pour les détails.

---

## 8. Vérification de l'installation

```bash
cd /home/thalyn/OrbisAlternis
./scripts/verifier-systeme.sh
```

Tous les indicateurs doivent être ✓ verts avant de lancer la diffusion.

---

## 9. Première diffusion test

```bash
# Ajouter une vidéo de test à la liste totale
./scripts/gestion-ldl.sh ajouter tot \
  "http://127.0.0.1:8080/btfs/QmbQb1kfwEmf4sqCUcccDYHBiuvKAsE4h8LQsQJ13VvZR2" \
  "Vidéo de test"

# Lancer la diffusion vers DLive uniquement (test)
./scripts/diffuser.sh -l ldl/ldl_tot.txt -p dlive -n
```

---

## Dépannage rapide

| Problème | Solution |
|----------|----------|
| `btfs daemon` ne démarre pas | Vérifier l'espace disque : `df -h ~/.btfs` |
| FFmpeg : `Connection refused` | Vérifier que nginx est actif : `sudo systemctl status nginx` |
| Kick : flux refusé | Vérifier que Stunnel est actif : `sudo systemctl status stunnel4` |
| Aucune vidéo BTFS accessible | Attendre la synchronisation BTFS (peut prendre plusieurs minutes) |

Voir [DIAGNOSTIC.md](DIAGNOSTIC.md) pour un dépannage approfondi.
