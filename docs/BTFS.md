# BTFS — Intégration BitTorrent File System

Guide d'utilisation de BTFS dans le cadre du projet Orbis Alternis.

---

## Qu'est-ce que BTFS ?

**BTFS** (BitTorrent File System) est un système de fichiers distribué basé sur le protocole BitTorrent et intégré à la blockchain **BTTC** (BitTorrent Chain, réseau Tron).

- Les fichiers sont identifiés par un **hash de contenu** (CID) : `QmXXXXX...` ou `bafyXXX...`
- Les fichiers sont récupérés depuis le réseau pair-à-pair
- Le nœud local expose une **passerelle HTTP** pour accéder aux fichiers

---

## Informations du nœud

| Paramètre | Valeur |
|-----------|--------|
| Version | 4.1.0-299483c |
| Architecture | arm64/linux |
| Dépôt local | `/home/thalyn/.btfs` |
| Identité du pair | `16Uiu2HAmCm6zxn93tjqZ3GpWqqkVVXXQdq418AxUmcH7jgW2vxsc` |
| Adresse BTTc | `0x0884232bCf26cE700fd78dbC626320b8C1a46Fe6` |
| Chaîne actuelle | `1029` (testnet BTTC) |
| Passerelle HTTP | `http://127.0.0.1:8080` |

---

## Démarrage du démon BTFS

### Mode manuel (testnet)
```bash
btfs daemon --chain-id 1029
```

### Mode manuel (mainnet — production)
```bash
btfs daemon --chain-id 199
```

### Via le service systemd (recommandé)
```bash
sudo systemctl start btfs
sudo systemctl status btfs
```

> Pour basculer du testnet au mainnet, modifier `BTFS_CHAINE_ID` dans `conf/orbis.conf` et redémarrer le service.

---

## Accéder à un fichier via la passerelle HTTP

```bash
# Accès direct par hash
curl -s "http://127.0.0.1:8080/btfs/QmbQb1kfwEmf4sqCUcccDYHBiuvKAsE4h8LQsQJ13VvZR2" -o sortie.mp4

# Vérifier l'existence d'un fichier (sans le télécharger)
curl -sf --max-time 15 --head \
  "http://127.0.0.1:8080/btfs/QmbQb1kfwEmf4sqCUcccDYHBiuvKAsE4h8LQsQJ13VvZR2"
```

---

## Ajouter des vidéos à BTFS

### Ajouter un fichier local

```bash
# Ajouter un fichier MP4
btfs add /chemin/vers/film.mp4
# → Retourne le hash CID : QmXXXXXXXXXX

# Ajouter un dossier entier
btfs add -r /chemin/vers/dossier/
```

### Épingler un fichier (éviter la suppression)

```bash
btfs pin add QmXXXXXXXXXX
btfs pin ls   # Lister les fichiers épinglés
```

### Vérifier l'état d'un fichier

```bash
# Informations sur un objet BTFS
btfs object stat QmXXXXXXXXXX

# Lister les blocs disponibles localement
btfs block stat QmXXXXXXXXXX
```

---

## Formats vidéo supportés

BTFS stocke les fichiers tels quels — tous les formats sont supportés.  
FFmpeg lit directement depuis la passerelle HTTP et gère les formats suivants :

| Format | Extension | Notes |
|--------|-----------|-------|
| MPEG-4 | `.mp4` | Format recommandé |
| Matroska | `.mkv` | Très courant |
| Audio Video Interleave | `.avi` | Ancien format, supporté |
| Ogg | `.ogv` | Format libre |
| WebM | `.webm` | Format libre web |

FFmpeg détecte automatiquement le format — pas besoin de spécifier l'extension dans l'URL BTFS.

---

## Résolution et formats d'image supportés

Le système adapte automatiquement toute résolution à 1080p maximum via FFmpeg, avec des **bandes noires** (letterbox ou pillarbox) pour conserver le ratio d'image :

| Ratio | Résolution native | Adaptation |
|-------|------------------|------------|
| 16:9  | 1920×1080 | Aucune (natif) |
| 16:9  | 1280×720 | Mise à l'échelle vers 1920×1080 |
| 4:3   | 1440×1080 | Bandes latérales (pillarbox) |
| 21:9  | 2560×1080 | Bandes supérieure/inférieure (letterbox) |
| 16:10 | 1920×1200 | Légère adaptation |

---

## Diagnostic BTFS

```bash
# Diagnostic complet BTFS
./scripts/diagnostic.sh --btfs

# Vérifier les pairs connectés
curl -s "http://127.0.0.1:5001/api/v1/swarm/peers" | python3 -m json.tool

# Consulter les journaux du démon
sudo journalctl -u btfs -f

# Statistiques du dépôt
btfs repo stat
```

---

## Passage testnet → mainnet

Quand le projet sera prêt pour la production :

1. Arrêter le service BTFS :
   ```bash
   sudo systemctl stop btfs
   ```

2. Modifier `conf/orbis.conf` :
   ```bash
   BTFS_CHAINE_ID="199"   # mainnet
   ```

3. Modifier le service systemd (`/etc/systemd/system/btfs.service`) :
   ```ini
   ExecStart=/usr/local/bin/btfs daemon --chain-id 199
   ```

4. Recharger et redémarrer :
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl start btfs
   ```

> **Note :** Les hashes BTFS restent identiques entre testnet et mainnet — seul le réseau de distribution change.
