# Guide de Résolution — Erreur RTMP "Input/output error"

## Résumé du problème

Vous recevez l'erreur suivante lors de la diffusion :

```
[out#0/flv @ 0x...] Error opening output rtmp://127.0.0.1:1935/diffusion/orbis: Input/output error
```

Cela signifie que **FFmpeg ne peut pas envoyer le flux vers nginx-rtmp**. Le problème vient de la configuration RTMP, pas de BTFS ou des plateformes.

## Diagnostic rapide

Exécutez d'abord le diagnostic RTMP :

```bash
cd ~/OrbisAlternis
./scripts/diagnostic.sh --rtmp
```

Cela va vérifier :
- ✓ nginx est-il actif ?
- ✓ Le port 1935 est-il ouvert ?
- ✓ La syntax nginx est-elle valide ?
- ✓ Le module RTMP est-il chargé ?
- ✓ Le bloc RTMP est-il généré et inclus ?
- ✓ Peut-on se connecter au port 1935 ?

## Résolution étape par étape

### Étape 1 : Vérifier que nginx est actif

```bash
sudo systemctl status nginx
```

**Si nginx est inactif :**
```bash
sudo systemctl start nginx
```

### Étape 2 : Vérifier que le module RTMP est installé

```bash
sudo nginx -T 2>&1 | grep rtmp
```

ou

```bash
ls -la /etc/nginx/modules-enabled/ | grep rtmp
```

**Si le module n'est pas installé :**
```bash
sudo apt update
sudo apt install -y libnginx-mod-rtmp
```

Puis redémarrez nginx :
```bash
sudo systemctl restart nginx
```

### Étape 3 : Générer le bloc RTMP

Le bloc RTMP doit être **généré dynamiquement** avec vos vraies clés de flux.

Lancez le script principal (il génère automatiquement le bloc) :

```bash
./scripts/diffuser.sh -l ldl/ldl_tot.txt -p dlive -n
```

Vérifiez que le fichier a été créé :

```bash
ls -la /etc/nginx/orbis-rtmp-block.conf
```

Regardez son contenu :

```bash
sudo cat /etc/nginx/orbis-rtmp-block.conf
```

Il doit ressembler à ceci :

```
rtmp {
    server {
        listen 1935;
        chunk_size 4096;
        max_message 1M;

        application diffusion {
            live on;
            record off;
            allow publish 127.0.0.1;
            deny publish all;
            allow play all;
            push rtmp://stream.dlive.tv/live/VOTRE_CLE_DLIVE;
            push rtmp://127.0.0.1:11935/app/VOTRE_CLE_KICK;
        }
    }
}
```

### Étape 4 : Vérifier l'inclusion du bloc dans nginx.conf

Le bloc RTMP doit être inclus **au niveau racine** de nginx.conf, **pas dans le bloc http{}**.

```bash
sudo grep "orbis-rtmp-block.conf" /etc/nginx/nginx.conf
```

**Si l'inclusion est absent :**

Ajoutez-la manuellement à la fin de `/etc/nginx/nginx.conf` :

```bash
echo "" | sudo tee -a /etc/nginx/nginx.conf
echo "# Orbis Alternis -- bloc RTMP" | sudo tee -a /etc/nginx/nginx.conf
echo "include /etc/nginx/orbis-rtmp-block.conf;" | sudo tee -a /etc/nginx/nginx.conf
```

### Étape 5 : Valider la syntax nginx

```bash
sudo nginx -t
```

Vous devez voir : `syntax is ok`

**Si la syntax est invalide :**

Affichez la config complète pour identifier l'erreur :

```bash
sudo nginx -T 2>&1 | head -100
```

Les erreurs courantes :
- Bloc `rtmp {}` mal placé (doit être au niveau racine, pas dans `http {}`)
- Directive `load_module` mal positionnée (doit être ligne 1)
- Accolades manquantes ou en surplus

### Étape 6 : Recharger nginx

```bash
sudo systemctl reload nginx
```

Vérifiez que le port 1935 est maintenant ouvert :

```bash
ss -tlnp | grep 1935
```

Vous devez voir une ligne avec `:1935` et `nginx`.

## Utiliser le script de correction automatique

Si vous préférez laisser un script corriger automatiquement, utilisez :

```bash
sudo ./scripts/fixer-rtmp.sh
```

Ce script va :
1. Nettoyer les anciennes configurations
2. Installer/vérifier le module RTMP
3. Générer le bloc RTMP
4. Inclure le bloc dans nginx.conf
5. Valider et recharger nginx
6. Tester que RTMP fonctionne

## Tester RTMP avec FFmpeg

Une fois les corrections appliquées, testez manuellement :

```bash
./scripts/diagnostic.sh --ffmpeg
```

Cela va envoyer une vidéo de test (couleur noire, 3 secondes) vers nginx-rtmp.

**Si le test réussit :**
- Vous verrez : `muxing overhead`
- Cela signifie que RTMP fonctionne maintenant

**Si vous avez encore "Input/output error" :**

Consultez les logs nginx en temps réel :

```bash
sudo tail -f /var/log/nginx/error.log
```

Puis relancez le diagnostic FFmpeg dans un autre terminal. Les erreurs s'afficheront dans les logs.

## Causes possibles et solutions

| Symptôme | Cause | Solution |
|----------|-------|----------|
| `Port 1935 not listening` | nginx inactif ou module RTMP absent | `sudo systemctl restart nginx` + `sudo apt install libnginx-mod-rtmp` |
| `syntax is not ok` | Bloc RTMP mal formé | Vérifiez `/etc/nginx/orbis-rtmp-block.conf` (accolades, indentation) |
| `Input/output error` | nginx refuse la connexion RTMP | Relancez `./scripts/diffuser.sh` + `sudo systemctl reload nginx` |
| `connection refused` | Pare-feu local bloque 1935 | `sudo ufw allow 1935/tcp` (si ufw est actif) |
| `module not found` | libnginx-mod-rtmp non installé | `sudo apt install libnginx-mod-rtmp` |

## Vérifications avancées

### Voir la config complète de nginx

```bash
sudo nginx -T
```

Cherchez le bloc `rtmp {}`. S'il n'est pas là, le bloc ne s'est pas chargé.

### Vérifier que nginx peut écrire dans ses répertoires

```bash
sudo chown -R www-data:www-data /var/log/nginx
sudo chown -R www-data:www-data /var/run/nginx
```

### Redémarrer nginx complètement (pas juste reload)

```bash
sudo systemctl restart nginx
```

Puis vérifiez :

```bash
sudo systemctl status nginx
```

## Après correction : Lancer la diffusion

Une fois RTMP rétabli, relancez la diffusion :

```bash
./scripts/diffuser.sh -l ldl/ldl_tot.txt -p dlive -n
```

Ou avec les deux plateformes :

```bash
./scripts/diffuser.sh -l ldl/ldl_tot.txt -p toutes -n
```

## Besoin d'aide ?

Si le problème persiste après tous ces diagnostics, collectez ces informations :

```bash
# Diagnostic complet
./scripts/diagnostic.sh --complet 2>&1 | tee ~/orbis-diag-$(date +%Y%m%d_%H%M%S).log

# Logs nginx
sudo tail -100 /var/log/nginx/error.log > ~/nginx-error.log

# Bloc RTMP
sudo cat /etc/nginx/orbis-rtmp-block.conf > ~/orbis-rtmp-block.log

# Config nginx (debut)
sudo head -50 /etc/nginx/nginx.conf > ~/nginx-conf-debut.log
```

Puis partagez ces fichiers pour diagnostic.