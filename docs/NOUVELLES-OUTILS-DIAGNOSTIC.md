# Nouveaux Outils de Diagnostic et Correction — Orbis Alternis

## Vue d'ensemble

Pour résoudre le problème **"Input/output error" FFmpeg code 251** que vous rencontrez avec RTMP, trois nouveaux outils ont été créés :

1. **`diagnostic.sh`** — Diagnostic approfondi de votre configuration RTMP
2. **`fixer-rtmp.sh`** — Correction automatique des problèmes courants
3. **`GUIDE-RAPIDE-RTMP.md`** — Guide en 5 minutes pour résoudre votre problème
4. **`RESOLUTION-RTMP.md`** — Guide complet de dépannage détaillé

---

## Outil 1 : `diagnostic.sh` — Diagnostic Complet

### Objectif

Identifier précisément ce qui empêche RTMP de fonctionner sur votre système.

### Utilisation

```bash
cd ~/OrbisAlternis

# Diagnostic RTMP uniquement (le plus important)
./scripts/diagnostic.sh --rtmp

# Diagnostic BTFS
./scripts/diagnostic.sh --btfs

# Test FFmpeg vers nginx-rtmp
./scripts/diagnostic.sh --ffmpeg

# Diagnostic complet (système + BTFS + RTMP + FFmpeg)
./scripts/diagnostic.sh --complet

# Afficher les derniers journaux de diffusion
./scripts/diagnostic.sh --journaux

# Afficher l'aide
./scripts/diagnostic.sh -h
```

### Ce que chaque option vérifie

#### `--rtmp`
Vérifie la configuration RTMP en 8 étapes :
1. ✓ nginx est-il actif ?
2. ✓ Le port RTMP (1935) est-il ouvert ?
3. ✓ La syntax nginx est-elle valide ?
4. ✓ Le module RTMP est-il chargé ?
5. ✓ Le bloc RTMP est-il généré ?
6. ✓ Le bloc RTMP est-il inclus dans nginx.conf ?
7. ✓ La connexion TCP au port 1935 fonctionne-t-elle ?
8. ✓ Les logs nginx ont-ils des erreurs ?

**Résultat :** Chaque point est marqué ✓ OK ou ✗ ERREUR

#### `--btfs`
Vérifie l'accès à BTFS :
1. ✓ Le démon BTFS est-il actif ?
2. ✓ La passerelle HTTP (port 8080) est-elle accessible ?
3. ✓ Peut-on accéder aux URLs BTFS réelles ?

#### `--ffmpeg`
Lance un test FFmpeg complet :
1. Crée une source vidéo de test (couleur noire, 3-5 secondes)
2. Envoie cette source vers `rtmp://127.0.0.1:1935/diffusion/test_orbis`
3. Affiche les logs FFmpeg
4. Indique si le push RTMP a réussi ou échoué

**Si FFmpeg réussit :**
```
✓ Push RTMP REUSSI (flux envoyé vers nginx)
```

**Si FFmpeg échoue :**
```
✗ ERREUR DE CONNEXION RTMP (Input/output error)
Le bloc RTMP refuse les connexions entrantes.
```

#### `--complet`
Exécute tous les diagnostics dans l'ordre (système, BTFS, RTMP, FFmpeg).

---

## Outil 2 : `fixer-rtmp.sh` — Correction Automatique

### Objectif

Corriger automatiquement les problèmes RTMP détectés par le diagnostic.

### Utilisation

```bash
# Lancer le correcteur
sudo ./scripts/fixer-rtmp.sh
```

**Important :** Vous devez avoir les privilèges `sudo` (cela modifie les fichiers nginx).

### Ce que le script corrige

Le script exécute 7 corrections dans cet ordre :

1. **Nettoyage des anciennes configurations**
   - Supprime les fichiers nginx obsolètes qui pourraient causer des conflits

2. **Installation du module RTMP**
   - Si `libnginx-mod-rtmp` manque, il l'installe

3. **Génération du bloc RTMP**
   - Crée `/etc/nginx/orbis-rtmp-block.conf` avec vos clés de flux

4. **Inclusion du bloc dans nginx.conf**
   - Ajoute `include /etc/nginx/orbis-rtmp-block.conf;` à la fin de `/etc/nginx/nginx.conf`

5. **Validation de la syntax nginx**
   - Lance `sudo nginx -t` pour vérifier qu'il n'y a pas d'erreurs

6. **Rechargement de nginx**
   - Lance `sudo systemctl reload nginx` pour appliquer les changements

7. **Vérification finale**
   - Teste que le port 1935 est maintenant ouvert et accessible

### Résultat attendu

À la fin du script, vous devez voir :

```
✓ Correction terminée : X changement(s) appliqué(s)

Prochaine étape : Relancer la diffusion
  $ ./scripts/diffuser.sh -l ldl/ldl_tot.txt -p dlive -n
```

---

## Workflow Recommandé

### Scénario 1 : Vous venez de rencontrer l'erreur 251

**Étapes (5 minutes max) :**

```bash
cd ~/OrbisAlternis

# 1. Diagnostiquer le problème (1 min)
./scripts/diagnostic.sh --rtmp

# 2. Corriger automatiquement (2 min)
sudo ./scripts/fixer-rtmp.sh

# 3. Tester FFmpeg (1 min)
./scripts/diagnostic.sh --ffmpeg

# 4. Si FFmpeg réussit, relancer la diffusion (1 min)
./scripts/diffuser.sh -l ldl/ldl_tot.txt -p dlive -n
```

### Scénario 2 : Vous avez modifié la config nginx manuellement

```bash
# 1. Vérifier que la syntax est valide
sudo nginx -t

# 2. Recharger nginx
sudo systemctl reload nginx

# 3. Vérifier que RTMP fonctionne
./scripts/diagnostic.sh --ffmpeg
```

### Scénario 3 : Vous avez changé les clés de flux DLive/Kick

```bash
# 1. Éditer la configuration
nano conf/orbis.conf
# → Changer DLIVE_CLE_FLUX et KICK_CLE_FLUX

# 2. Relancer le script diffuser.sh pour régénérer le bloc RTMP
./scripts/diffuser.sh -l ldl/ldl_tot.txt -p dlive -n
# → Cela génère automatiquement un nouveau /etc/nginx/orbis-rtmp-block.conf

# 3. Vérifier
./scripts/diagnostic.sh --ffmpeg
```

---

## Guides de Dépannage

### Pour une résolution rapide (5 minutes)
→ **[GUIDE-RAPIDE-RTMP.md](GUIDE-RAPIDE-RTMP.md)**

Contient :
- Les 3 commandes exactes à exécuter
- Les résultats attendus
- Les 30 prochaines secondes après

### Pour un dépannage approfondi
→ **[RESOLUTION-RTMP.md](RESOLUTION-RTMP.md)**

Contient :
- Résolution étape par étape (manuelle)
- Explication de chaque problème possible
- Solutions pour les cas complexes
- Tableau des causes/solutions

### Documentation technique
→ **[docs/](../)**

- `INSTALLATION.md` — Installation du système
- `CONFIGURATION.md` — Paramètres et tuning
- `BTFS.md` — Configuration BTFS
- `LISTES-LECTURE.md` — Gestion des vidéos

---

## Exemples de Sortie

### Diagnostic RTMP Réussi

```
ℹ DIAGNOSTIC RTMP
──────────────────────────────────────────

ℹ 1. nginx est-il actif ?
✓ nginx actif

ℹ 2. Port RTMP (1935) ouvert ?
✓ Port 1935 en ecoute
    tcp  LISTEN  0  511  0.0.0.0:1935  0.0.0.0:*

ℹ 3. Vérification de la syntax nginx...
✓ Syntax nginx valide

ℹ 4. Vérification du module RTMP...
✓ Module RTMP chargé

ℹ 5. Vérification du bloc RTMP généré...
✓ Fichier /etc/nginx/orbis-rtmp-block.conf présent

ℹ 6. Vérification de l'inclusion du bloc RTMP...
✓ Inclusion du bloc RTMP présente dans nginx.conf

ℹ 7. Test de connexion TCP sur 127.0.0.1:1935...
✓ Connexion TCP possible sur le port 1935

ℹ 8. Vérification des erreurs nginx récentes...
✓ Aucune erreur critique dans les logs nginx

ℹ Diagnostic RTMP terminé
```

### Test FFmpeg Réussi

```
ℹ TEST FINAL : Verification que RTMP fonctionne
──────────────────────────────────────────────────

    Logs FFmpeg du test :
    ───────────────────────────────
    ffmpeg version 4.4.2 built with gcc 11.2.0
    frame= 147 fps= 50 q=-1.0 Lqsize=   0KB time=00:00:04.92 bitrate=1989.4kbits/s
    muxing overhead: 0.159291%
    ───────────────────────────────

✓ Push RTMP REUSSI (flux envoyé vers nginx)
ℹ Le problème n'est PAS dans la configuration RTMP.
ℹ Vérifiez les clés de flux DLive/Kick dans orbis.conf
```

### Test FFmpeg Échoué

```
✗ ERREUR DE CONNEXION RTMP (Input/output error)

    DIAGNOSTIC :
    ────────────
    Le bloc RTMP refuse les connexions entrantes.
    Causes possibles :
      1. Les directives 'allow publish' / 'deny publish' bloquent 127.0.0.1
      2. Le bloc RTMP a une erreur de syntax
      3. nginx-rtmp module version obsolète ou bugué

    Actions à prendre :
      → Vérifier /etc/nginx/orbis-rtmp-block.conf (voir ci-dessus)
      → Relancer : sudo systemctl restart nginx
      → Relancer le test : ./scripts/diagnostic.sh --ffmpeg
```

---

## Fichiers Générés et Modifiés

### Fichiers générés par `diffuser.sh` (et `fixer-rtmp.sh`)

| Fichier | Emplacement | Description |
|---------|-------------|-------------|
| `orbis-rtmp-block.conf` | `/etc/nginx/` | Bloc RTMP avec vos clés de flux |
| `orbis-stats.conf` | `/etc/nginx/sites-enabled/` | Serveur HTTP pour les stats RTMP |

### Fichiers modifiés

| Fichier | Modification |
|---------|--------------|
| `/etc/nginx/nginx.conf` | Ajout de `include /etc/nginx/orbis-rtmp-block.conf;` à la fin |

### Fichiers de logs

| Fichier | Description |
|---------|-------------|
| `~/OrbisAlternis/journaux/diffusion_*.log` | Logs de chaque diffusion |
| `/var/log/nginx/error.log` | Erreurs nginx |
| `/var/log/nginx/access.log` | Accès nginx |

---

## Cas d'Usage Spécifiques

### J'ai une erreur de syntax nginx

```bash
# Voir l'erreur exacte
sudo nginx -t

# Voir la config complète avec ligne de problème
sudo nginx -T 2>&1 | head -100

# Corriger avec fixer-rtmp.sh
sudo ./scripts/fixer-rtmp.sh
```

### nginx ne redémarre pas après fixer-rtmp.sh

```bash
# Voir pourquoi
sudo systemctl status nginx

# Voir les erreurs du service
sudo journalctl -u nginx -n 50

# Redémarrer manuellement avec plus d'info
sudo systemctl restart nginx -vvv
```

### Le port 1935 est déjà utilisé

```bash
# Voir qui l'utilise
sudo lsof -i :1935

# Si c'est un ancien process nginx, tuer-le
sudo pkill -f nginx

# Puis redémarrer
sudo systemctl start nginx
```

### Je veux revenir à une config de travail antérieure

```bash
# Le script génère automatiquement les fichiers
# Aucune sauvegarde n'existe, mais c'est OK car
# les fichiers générés sont déterministes.

# Relancer simplement :
sudo ./scripts/fixer-rtmp.sh
# qui régénère tout correctement
```

---

## Support et Aide

### Besoin d'aide ?

1. **Commencez par :** [GUIDE-RAPIDE-RTMP.md](GUIDE-RAPIDE-RTMP.md)
2. **Si ça ne suffit pas :** [RESOLUTION-RTMP.md](RESOLUTION-RTMP.md)
3. **Pour le dépannage technique :** Consultez ce document

### Collecter des diagnostics pour demander de l'aide

```bash
# Créer un dossier de diagnostics
mkdir -p ~/orbis-diagnostics

# Diagnostic complet
./scripts/diagnostic.sh --complet 2>&1 | tee ~/orbis-diagnostics/diagnostic.log

# Logs nginx
sudo tail -200 /var/log/nginx/error.log > ~/orbis-diagnostics/nginx-errors.log

# Bloc RTMP généré
sudo cat /etc/nginx/orbis-rtmp-block.conf > ~/orbis-diagnostics/orbis-rtmp-block.conf

# Config nginx (début)
sudo head -100 /etc/nginx/nginx.conf > ~/orbis-diagnostics/nginx-conf-head.log

# Dernier journal de diffusion
tail -200 ~/OrbisAlternis/journaux/diffusion_*.log | head -200 > ~/orbis-diagnostics/derniere-diffusion.log

# Compresser et partager
tar czf ~/orbis-diagnostics.tar.gz ~/orbis-diagnostics/
# Puis partagez le fichier pour support
```

---

## Résumé

| Outil | Quand l'utiliser | Durée |
|-------|-----------------|-------|
| `diagnostic.sh --rtmp` | D'abord, pour identifier le problème | 1 min |
| `fixer-rtmp.sh` | Après le diagnostic, pour corriger | 2-3 min |
| `diagnostic.sh --ffmpeg` | Après correction, pour vérifier | 1 min |
| `diffuser.sh` | Quand RTMP fonctionne, pour lancer la diffusion | variable |

**Total pour résoudre votre problème :** ~5 minutes

---

## Prochaines Étapes

Une fois RTMP réparé et fonctionnel :

1. **Consulter CONFIGURATION.md** pour optimiser les bitrates
2. **Consulter LISTES-LECTURE.md** pour gérer vos vidéos BTFS
3. **Ajouter des options** : filigrane (`-f`), webcam (`-w`), boucle (`-b`), mélange (`-m`)
4. **Configurer un lancement automatique** (systemd, cron, etc.)

Bon courage ! 🚀