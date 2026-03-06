# 🚀 COMMENCER ICI — Résolution du problème RTMP

## Votre situation

Vous avez cette erreur lors de la diffusion :
```
[AVERT ] FFmpeg code 251 pour : [Titre à renseigner]
Error opening output rtmp://127.0.0.1:1935/diffusion/orbis: Input/output error
```

**C'est réparable en 5 minutes !** 👇

---

## 3 Commandes à Exécuter

### 1️⃣ Lancer le diagnostic (1 minute)

```bash
cd ~/OrbisAlternis
./scripts/diagnostic.sh --rtmp
```

Cela va vérifier votre configuration RTMP et vous dire ce qui ne va pas.

**Résultat attendu :** Une liste de vérifications avec ✓ OK ou ✗ ERREUR

---

### 2️⃣ Corriger automatiquement (2-3 minutes)

```bash
sudo ./scripts/fixer-rtmp.sh
```

Ce script corrige automatiquement tous les problèmes RTMP détectés.

**Résultat attendu :** 
```
✓ Correction terminée : X changement(s) appliqué(s)

Prochaine étape : Relancer la diffusion
  $ ./scripts/diffuser.sh -l ldl/ldl_tot.txt -p dlive -n
```

---

### 3️⃣ Tester que ça marche (1 minute)

```bash
./scripts/diagnostic.sh --ffmpeg
```

Cela envoie une vidéo de test vers nginx-rtmp pour vérifier que la connexion RTMP fonctionne.

**Résultat attendu :**
```
✓ Push RTMP REUSSI (flux envoyé vers nginx)
```

---

## 4️⃣ Relancer la diffusion

Si le test FFmpeg a réussi :

```bash
./scripts/diffuser.sh -l ldl/ldl_tot.txt -p dlive -n
```

**La diffusion devrait maintenant fonctionner sans erreur 251 !** ✅

---

## Si ça ne marche pas

Deux possibilités :

### Option A : Guide rapide (10 minutes)

Lisez le guide ultra-rapide (très court et clair) :

```bash
cat docs/GUIDE-RAPIDE-RTMP.md
```

Puis relancez les 3 commandes ci-dessus.

### Option B : Guide complet (30 minutes)

Si vous avez toujours un problème, consultez le guide détaillé :

```bash
cat docs/RESOLUTION-RTMP.md
```

Cherchez votre situation exacte dans le tableau "Causes possibles et solutions".

---

## Vérification rapide

Avant de commencer, assurez-vous que vous avez les clés de flux remplies :

```bash
grep "DLIVE_CLE_FLUX\|KICK_CLE_FLUX" ~/OrbisAlternis/conf/orbis.conf
```

Si vous voyez des lignes vides ou `DLIVE_CLE_FLUX=""`, **remplissez-les d'abord** :

```bash
nano ~/OrbisAlternis/conf/orbis.conf
# Puis trouvez les lignes DLIVE_CLE_FLUX et KICK_CLE_FLUX
# Et remplissez-les avec vos vraies clés
# Puis Ctrl+X, Y, Entrée pour sauvegarder
```

---

## Fichiers utiles

| Fichier | Quand le lire |
|---------|---|
| **GUIDE-RAPIDE-RTMP.md** | Vous êtes impatient (5-10 min) |
| **RESOLUTION-RTMP.md** | Vous voulez comprendre ou ça ne marche pas (30 min) |
| **NOUVELLES-OUTILS-DIAGNOSTIC.md** | Vous voulez savoir comment fonctionnent les outils |
| **PROBLEME-RESOLUTION.txt** | Résumé complet du problème et de la solution |

---

## Commandes utiles si bloqué

```bash
# Voir le statut de nginx
sudo systemctl status nginx

# Voir si le port 1935 est ouvert
ss -tlnp | grep 1935

# Recharger nginx après corrections
sudo systemctl reload nginx

# Voir les erreurs nginx
sudo tail -50 /var/log/nginx/error.log

# Voir le dernier journal de diffusion
tail -100 ~/OrbisAlternis/journaux/diffusion_*.log
```

---

## ⚡ Résumé ultra-rapide

| Étape | Commande | Temps |
|-------|----------|-------|
| 1. Diagnostic | `./scripts/diagnostic.sh --rtmp` | 1 min |
| 2. Correction | `sudo ./scripts/fixer-rtmp.sh` | 2-3 min |
| 3. Test | `./scripts/diagnostic.sh --ffmpeg` | 1 min |
| 4. Diffusion | `./scripts/diffuser.sh -l ldl/ldl_tot.txt -p dlive -n` | variable |

**Total : 5 minutes**

---

## Prochaines étapes après correction

Une fois RTMP réparé :

```bash
# Diffuser vers les 2 plateformes (DLive + Kick)
./scripts/diffuser.sh -l ldl/ldl_tot.txt -p toutes -n

# Diffuser en boucle infini
./scripts/diffuser.sh -l ldl/ldl_tot.txt -p toutes -b

# Ajouter un filigrane (logo)
./scripts/diffuser.sh -l ldl/ldl_tot.txt -p toutes -f -n

# Mélanger aléatoirement
./scripts/diffuser.sh -l ldl/ldl_tot.txt -p toutes -m -n
```

---

**🎯 Prêt à commencer ?**

Exécutez cette commande MAINTENANT :

```bash
cd ~/OrbisAlternis
./scripts/diagnostic.sh --rtmp
```

Puis suivez les 3 étapes ci-dessus. ✅

Vous aurai fini dans 5 minutes ! 🚀