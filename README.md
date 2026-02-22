# Orbis Alternis — Diffuseur RTMPS/BTFS pour ARM64

**Système de diffusion en continu de listes de lecture vidéo depuis BTFS vers les plateformes de streaming DLive et Kick, piloté par un Raspberry Pi 4.**

---

## Présentation

**Orbis Alternis** est un projet de diffusion de films de science-fiction hébergés sur le réseau distribué BTFS (BitTorrent File System), diffusés en temps réel vers :
- **DLive** via RTMP
- **Kick** via RTMPS (chiffré TLS)
- *(à venir)* Site web personnel avec lecteur DASH

Le système tourne nativement sur **Raspberry Pi 4** (ARM64), sans aucune dépendance propriétaire.

---

## Caractéristiques

| Fonctionnalité | Statut |
|----------------|--------|
| Architecture ARM64 native (Raspberry Pi 4) | ✅ |
| RTMP vers DLive | ✅ |
| RTMPS chiffré (Stunnel + TLS) vers Kick | ✅ |
| Sources vidéo depuis BTFS (réseau distribué) | ✅ |
| Listes de lecture multiples et thématiques | ✅ |
| Résolutions variables (16:9, 16:10, 21:9...) adaptées en 1080p | ✅ |
| Encodeur logiciel libx264 et matériel h264_v4l2m2m | ✅ |
| Scripts 100% Bash — zéro dépendance supplémentaire | ✅ |
| Documentation en français | ✅ |
| Filigrane (logo) à la volée | ✅ (configurable) |
| Surcouche webcam (watch party) | ✅ (configurable) |
| Lecteur DASH / mini-site web | 🔜 (planifié) |
| Bot de chat IA (Kick + DLive) | 🔜 (planifié) |

---

## Architecture technique

```
BTFS (pair-à-pair)
    │  passerelle HTTP :8080
    ▼
FFmpeg (encodage H.264/AAC une seule fois)
    │  RTMP local
    ▼
nginx + module RTMP (relais local :1935)
    │               │
    ▼               ▼
 DLive          Stunnel (:11935)
 RTMP               │ TLS/RTMPS
                    ▼
                  Kick
```

**Technologies utilisées :**
- `nginx` + `libnginx-mod-rtmp` — Serveur et relais RTMP
- `stunnel4` — Chiffrement TLS pour RTMPS (Kick)
- `btfs` 4.1.0 — Nœud BTFS/BTTC (testnet → mainnet)
- `ffmpeg` — Transcodage et normalisation vidéo
- `bash` — Orchestration complète

---

## Structure du projet

```
OrbisAlternis/
├── conf/
│   ├── orbis.conf              ← Configuration principale (à personnaliser)
│   ├── stunnel-kick.conf       ← Tunnel TLS pour Kick
│   └── nginx-rtmp.conf         ← Modèle nginx (généré automatiquement)
├── ldl/
│   ├── ldl_tot.txt             ← Liste de lecture complète
│   ├── ldl_dystopies.txt
│   ├── ldl_IA.txt
│   └── ... (14 listes thématiques)
├── img/                        ← Logo et images (filigrane)
├── journaux/                   ← Journaux de diffusion
├── scripts/
│   ├── diffuser.sh             ← Script principal ▶
│   ├── gestion-ldl.sh          ← Gestion des listes de lecture
│   ├── verifier-systeme.sh     ← Vérification pré-diffusion
│   └── diagnostic.sh           ← Outil de diagnostic
└── docs/
    ├── INSTALLATION.md
    ├── CONFIGURATION.md
    ├── LISTES-LECTURE.md
    ├── RTMPS-DLIVE-KICK.md
    ├── BTFS.md
    └── DIAGNOSTIC.md
```

---

## Démarrage rapide

```bash
# 1. Cloner le projet sur le Raspberry Pi
git clone https://github.com/Thalyn-/diffuseur-rtmps-btfs-ARM64.git OrbisAlternis
cd OrbisAlternis
chmod +x scripts/*.sh

# 2. Configurer (clés de flux, chemins...)
nano conf/orbis.conf

# 3. Vérifier que tout est en ordre
./scripts/verifier-systeme.sh

# 4. Lancer la diffusion
./scripts/diffuser.sh -l ldl/ldl_tot.txt -p toutes
```

Pour l'installation complète, voir **[docs/INSTALLATION.md](docs/INSTALLATION.md)**.

---

## Options de diffusion

```bash
./scripts/diffuser.sh -h

  -l <fichier>    Liste de lecture (défaut : ldl/ldl_tot.txt)
  -p <cible>      dlive | kick | toutes
  -m              Mélanger aléatoirement
  -b              Forcer le bouclage
  -n              Lecture unique sans boucle
  -f              Activer le filigrane (logo)
  -w              Activer la surcouche webcam
```

---

## Nœud BTFS

- **Réseau actuel :** testnet BTTC (chain-id 1029)
- **Passage en production :** modifier `BTFS_CHAINE_ID="199"` dans `conf/orbis.conf`

---

## Licence

Projet libre — voir les conditions d'utilisation des plateformes DLive et Kick ainsi que les droits applicables aux œuvres diffusées.

---

## Feuille de route

- [x] Diffusion RTMP/RTMPS depuis BTFS
- [x] Gestion des listes de lecture thématiques
- [x] Filigrane et surcouche webcam
- [ ] Mini-site web avec lecteur DASH
- [ ] Bot de chat IA pour Kick et DLive (`!infos`, `!analyse`)
- [ ] Passage en production mainnet BTTC
