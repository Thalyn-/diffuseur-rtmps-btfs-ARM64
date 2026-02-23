# Diagnostic et résolution de problèmes — Orbis Alternis

---

## Outil de diagnostic intégré

```bash
# Diagnostic rapide (recommandé en premier)
./scripts/diagnostic.sh --rapide

# Diagnostic complet avec test FFmpeg (utile avant de signaler un problème)
./scripts/diagnostic.sh --complet

# Diagnostics spécifiques
./scripts/diagnostic.sh --btfs      # BTFS uniquement
./scripts/diagnostic.sh --reseau    # Connectivité réseau
./scripts/diagnostic.sh --ffmpeg    # Test d'encodage FFmpeg
./scripts/diagnostic.sh --journaux  # Derniers journaux de diffusion
```

---

## Problèmes courants

### ❌ Le flux ne démarre pas

**Symptôme :** `diffuser.sh` se lance mais aucun flux n'apparaît sur la plateforme.

**Vérifications :**
```bash
# 1. nginx actif ?
sudo systemctl status nginx
sudo nginx -t  # Vérifier la configuration

# 2. Stunnel actif (pour Kick) ?
sudo systemctl status stunnel4
journalctl -u stunnel4 --since "5 min ago"

# 3. FFmpeg peut-il lire la source BTFS ?
./scripts/diagnostic.sh --ffmpeg

# 4. La clé de flux est-elle correcte ?
grep CLE_FLUX /home/thalyn/OrbisAlternis/conf/orbis.conf
```

---

### ❌ Erreur BTFS : source inaccessible

**Symptôme :** `[AVERT] Source inaccessible` dans les journaux.

**Causes possibles :**

| Cause | Solution |
|-------|----------|
| Démon BTFS non démarré | `sudo systemctl start btfs` |
| Fichier non encore mis en cache | Attendre 1–5 minutes après le premier accès |
| Hash BTFS incorrect | Vérifier le hash dans la liste de lecture |
| Réseau pair-à-pair saturé | Vérifier `btfs swarm peers` |

```bash
# Tester manuellement une URL BTFS
curl -v --max-time 30 \
  "http://127.0.0.1:8080/btfs/QmbQb1kfwEmf4sqCUcccDYHBiuvKAsE4h8LQsQJ13VvZR2"

# Vérifier les pairs BTFS
curl -s "http://127.0.0.1:5001/api/v1/swarm/peers" | grep -c '"Addr"'
```

---

### ❌ Kick refuse le flux (RTMPS)

**Symptôme :** Connexion rejetée vers Kick, DLive fonctionne.

```bash
# 1. Stunnel est-il actif ?
sudo systemctl status stunnel4
ss -tlnp | grep 11935

# 2. Le port Kick est-il accessible ?
timeout 5 bash -c ">/dev/tcp/fa723fc1b171.global-contribute.live-video.net/443" \
  && echo "OK" || echo "BLOQUÉ"

# 3. Certificats TLS à jour ?
sudo update-ca-certificates

# 4. Tester la connexion TLS manuellement
openssl s_client -connect fa723fc1b171.global-contribute.live-video.net:443 \
  -brief 2>&1 | head -5
```

---

### ❌ Surcharge CPU du Raspberry Pi 4

**Symptôme :** Flux saccadé, CPU > 95%, surchauffe.

```bash
# Vérifier la charge en temps réel
htop
vcgencmd measure_temp

# Solution 1 : utiliser l'encodeur matériel du Pi4
# Modifier conf/orbis.conf :
ENCODEUR_VIDEO="h264_v4l2m2m"

# Vérifier la disponibilité de l'encodeur matériel
ls -la /dev/video*
v4l2-ctl --list-devices

# Solution 2 : réduire le débit
DLIVE_BITRATE_VIDEO=3000
KICK_BITRATE_VIDEO=4000
```

> L'encodeur matériel `h264_v4l2m2m` réduit la charge CPU de ~80% à ~20%.

---

### ❌ Flux vidéo avec bandes noires incorrectes

**Symptôme :** Image déformée ou bandes noires mal placées.

```bash
# Vérifier les informations de la source
ffprobe -v quiet -print_format json -show_streams \
  "http://127.0.0.1:8080/btfs/QmbQb1kfwEmf4sqCUcccDYHBiuvKAsE4h8LQsQJ13VvZR2" \
  | python3 -m json.tool | grep -E 'width|height|display_aspect_ratio'
```

Le filtre FFmpeg utilisé gère automatiquement tous les ratios — si le problème persiste, vérifier que la source n'a pas de métadonnées de rotation incorrectes.

---

### ❌ `nginx: configuration file test failed`

```bash
# Afficher les erreurs détaillées
sudo nginx -T 2>&1 | head -30

# Cause fréquente : module RTMP non chargé
grep 'load_module' /etc/nginx/nginx.conf
# Doit contenir : load_module modules/ngx_rtmp_module.so;

# Vérifier que le module est installé
ls /usr/lib/nginx/modules/ | grep rtmp
```

---

### ❌ Stunnel : `SSL_CTX_use_certificate_file` échoue

```bash
# Vérifier les certificats système
ls /etc/ssl/certs/ | grep -i "ca\|root"

# Mettre à jour les certificats
sudo apt install --reinstall ca-certificates
sudo update-ca-certificates --fresh
```

---

## Journaux et surveillance

### Journaux de diffusion

```bash
# Journal du dernier lancement
ls -t /home/thalyn/OrbisAlternis/journaux/diffusion_*.log | head -1 | xargs tail -100

# Suivre la diffusion en cours
tail -f /home/thalyn/OrbisAlternis/journaux/diffusion_$(date +%Y%m%d)*.log 2>/dev/null
```

### Journaux système

```bash
sudo journalctl -u nginx -f           # Nginx
sudo journalctl -u stunnel4 -f        # Stunnel
sudo journalctl -u btfs -f            # BTFS
tail -f /var/log/stunnel4/stunnel.log  # Stunnel détaillé
```

### Surveiller les ressources en temps réel

```bash
# Charge CPU, mémoire, température
watch -n 2 'echo "CPU: $(top -bn1 | grep Cpu | awk "{print \$2}")%" ; \
            echo "RAM: $(free -m | awk "/Mem/{print \$3}" )Mo utilisés" ; \
            echo "Temp: $(vcgencmd measure_temp)"'
```

---

## Signaler un problème

Inclure dans votre rapport :

1. La sortie de `./scripts/diagnostic.sh --complet`
2. Les 50 dernières lignes du journal de diffusion
3. La sortie de `sudo nginx -T`
4. La sortie de `journalctl -u stunnel4 --since "10 min ago"`
