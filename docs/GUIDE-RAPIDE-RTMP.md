# Guide Ultra-Rapide — Fixer le problème RTMP en 5 minutes

## Votre Situation Actuelle

Vous lancez la diffusion et vous recevez :

```
[AVERT ] FFmpeg code 251 pour : [Titre à renseigner]
Error opening output rtmp://127.0.0.1:1935/diffusion/orbis: Input/output error
```

**Le problème :** FFmpeg ne peut pas envoyer le flux vers nginx-rtmp.

---

## Solution Rapide (3 commandes)

Exécutez ces 3 commandes dans cet ordre exact sur votre Raspberry Pi :

### 1️⃣ Lancer le diagnostic RTMP

```bash
cd ~/OrbisAlternis
./scripts/diagnostic.sh --rtmp
```

**Attendez** que le diagnostic se termine. Il va vérifier votre config et vous dire exactement ce qui ne va pas.

### 2️⃣ Appliquer les corrections automatiques

```bash
sudo ./scripts/fixer-rtmp.sh
```

Ce script va :
- Installer le module RTMP s'il manque
- Générer la config nginx avec vos clés de flux
- Recharger nginx
- Vérifier que tout fonctionne

**Attendez** que le script se termine (2-3 minutes max).

### 3️⃣ Tester FFmpeg vers RTMP

```bash
./scripts/diagnostic.sh --ffmpeg
```

Cela va envoyer une vidéo de test (couleur noire, 3 secondes) vers nginx-rtmp.

**Résultat attendu :**
```
✓ Push RTMP REUSSI (flux envoyé vers nginx)
```

ou

```
✗ ERREUR DE CONNEXION RTMP (Input/output error)
```

---

## Si le test FFmpeg réussit ✅

Relancez la diffusion :

```bash
./scripts/diffuser.sh -l ldl/ldl_tot.txt -p dlive -n
```

Normalement, ça devrait fonctionner maintenant. La vidéo doit se lancer sans erreur 251.

---

## Si le test FFmpeg échoue toujours ❌

Consultez ces sections du guide détaillé :

**docs/RESOLUTION-RTMP.md** :
- Section "Dépannage Avancé" → Voir les logs nginx
- Section "Causes possibles" → Trouver votre cas exact
- Section "Vérifications avancées" → Tests manuels

Ou exécutez le diagnostic complet pour plus de détails :

```bash
./scripts/diagnostic.sh --complet 2>&1 | tee ~/diag-$(date +%Y%m%d_%H%M%S).log
```

---

## Checklist de 30 secondes

Avant de relancer, vérifiez rapidement :

```bash
# 1. nginx écoute sur le port 1935 ?
ss -tlnp | grep 1935

# 2. Le bloc RTMP est généré ?
sudo cat /etc/nginx/orbis-rtmp-block.conf | head -5

# 3. nginx a pas d'erreurs de syntax ?
sudo nginx -t
```

**Tous les 3 doivent être OK ✓**

---

## Si ça ne marche vraiment pas

**Étape atomique finale :** Redémarrage complet

```bash
# Arrêter complètement
sudo systemctl stop nginx

# Attendre 2 secondes
sleep 2

# Relancer
sudo systemctl start nginx

# Vérifier
sudo systemctl status nginx
```

Puis retestez avec :

```bash
./scripts/diagnostic.sh --ffmpeg
```

---

## Liens vers le dépannage détaillé

- **Guide complet :** `docs/RESOLUTION-RTMP.md`
- **Logs de diffusion :** `journaux/diffusion_*.log`
- **Logs nginx :** `sudo tail -50 /var/log/nginx/error.log`

---

## Questions rapides

**Q: Combien de temps ça prend ?**  
A: 3-5 minutes max pour les 3 commandes.

**Q: Faut-il redémarrer le Pi ?**  
A: Non, juste `sudo ./scripts/fixer-rtmp.sh` suffit.

**Q: C'est dangereux ?**  
A: Non, le script ne fait que recharger nginx, pas de perte de données.

**Q: Et mes clés de flux DLive/Kick ?**  
A: Vérifiez qu'elles sont dans `conf/orbis.conf` avant de lancer `fixer-rtmp.sh`.

```bash
grep "DLIVE_CLE_FLUX" ~/OrbisAlternis/conf/orbis.conf
grep "KICK_CLE_FLUX" ~/OrbisAlternis/conf/orbis.conf
```

Si elles sont vides, remplissez-les d'abord, puis relancez `fixer-rtmp.sh`.

---

**Bon courage ! Vous êtes presque là.** 🚀