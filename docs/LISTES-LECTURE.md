# Listes de lecture — Orbis Alternis

Gestion complète des listes de lecture (LDL) de vidéos stockées sur BTFS.

---

## Structure des fichiers

```
ldl/
├── ldl_tot.txt              ← Liste complète (toutes les vidéos)
├── ldl_dystopies.txt
├── ldl_IA.txt
├── ldl_origines-SF.txt
├── ldl_40-70.txt
├── ldl_espace-cosmos.txt
├── ldl_posthumain.txt
├── ldl_temps.txt
├── ldl_ecologie.txt
├── ldl_simulation.txt
├── ldl_bio-genetique.txt
├── ldl_politique.txt
├── ldl_philosophie.txt
├── ldl_anime-SF.txt
└── ldl_cyberpunk.txt
```

---

## Format d'un fichier de liste de lecture

```bash
# =============================================================
# ldl_[thematique].txt — Description de la thématique
# =============================================================
# FORMAT : URL_BTFS  # Titre (Réalisateur, Année)
# Les lignes commençant par # sont des commentaires (ignorées)
# =============================================================

http://127.0.0.1:8080/btfs/QmXXXXXX  # 2001 : L'Odyssée de l'espace (Kubrick, 1968)
http://127.0.0.1:8080/btfs/QmYYYYYY  # Solaris (Tarkovski, 1972)
```

### Règles de format

- Une URL par ligne
- L'URL doit commencer par `http://` ou `https://`
- Le titre est optionnel, séparé par `  #` (deux espaces puis dièse)
- Les hashes BTFS bruts (`QmXXX...`) sont aussi acceptés par `gestion-ldl.sh`
- Les lignes vides et commentaires (`# ...`) sont ignorés

---

## Utilisation du script `gestion-ldl.sh`

### Lister toutes les listes disponibles

```bash
./scripts/gestion-ldl.sh lister
```

Affiche un tableau avec le nom, le nombre d'entrées et la description de chaque liste.

### Afficher le contenu d'une liste

```bash
# Ces trois formes sont équivalentes :
./scripts/gestion-ldl.sh afficher ldl_dystopies.txt
./scripts/gestion-ldl.sh afficher ldl_dystopies
./scripts/gestion-ldl.sh afficher dystopies
```

### Ajouter une vidéo

```bash
# Avec URL complète
./scripts/gestion-ldl.sh ajouter tot \
  "http://127.0.0.1:8080/btfs/QmbQb1kfwEmf4sqCUcccDYHBiuvKAsE4h8LQsQJ13VvZR2" \
  "Blade Runner (Scott, 1982)"

# Avec hash BTFS brut (l'URL est construite automatiquement)
./scripts/gestion-ldl.sh ajouter dystopies \
  "QmbQb1kfwEmf4sqCUcccDYHBiuvKAsE4h8LQsQJ13VvZR2" \
  "1984 (Radford, 1984)"
```

> Un film ajouté à une liste thématique doit aussi être ajouté manuellement à `ldl_tot.txt` si souhaité.

### Supprimer une vidéo

```bash
./scripts/gestion-ldl.sh supprimer dystopies \
  "http://127.0.0.1:8080/btfs/QmbQb1kfwEmf4sqCUcccDYHBiuvKAsE4h8LQsQJ13VvZR2"
```

### Créer une nouvelle liste thématique

```bash
./scripts/gestion-ldl.sh creer "space-opera" "Space opéra et épopées galactiques"
```

Crée le fichier `ldl/ldl_space-opera.txt` avec l'en-tête pré-rempli.

### Vérifier l'accessibilité des sources

```bash
# Vérifier toutes les URLs d'une liste (nécessite BTFS en cours d'exécution)
./scripts/gestion-ldl.sh verifier ldl_tot.txt
```

Affiche pour chaque entrée si la source BTFS est accessible ou non.

### Statistiques

```bash
# Statistiques de toutes les listes
./scripts/gestion-ldl.sh stats

# Statistiques d'une liste spécifique
./scripts/gestion-ldl.sh stats ldl_IA
```

### Supprimer les doublons

```bash
./scripts/gestion-ldl.sh deduplication ldl_tot.txt
```

### Exporter une liste

```bash
# Format TXT (copie simple)
./scripts/gestion-ldl.sh exporter ldl_tot txt

# Format M3U (compatible lecteurs multimédia)
./scripts/gestion-ldl.sh exporter ldl_tot m3u

# Format JSON (pour intégrations futures — lecteur DASH, bot de chat)
./scripts/gestion-ldl.sh exporter ldl_tot json
```

---

## Lancer la diffusion depuis une liste

```bash
# Liste totale, toutes les plateformes, en boucle
./scripts/diffuser.sh -l ldl/ldl_tot.txt -p toutes

# Liste dystopies, Kick uniquement, ordre aléatoire
./scripts/diffuser.sh -l ldl/ldl_dystopies.txt -p kick -m

# Liste IA, DLive uniquement, lecture unique (pas de boucle)
./scripts/diffuser.sh -l ldl/ldl_IA.txt -p dlive -n
```

---

## Bonnes pratiques

1. **Toujours tester** l'accessibilité avant diffusion :
   ```bash
   ./scripts/gestion-ldl.sh verifier ldl_tot.txt
   ```

2. **Maintenir la liste totale** : chaque vidéo dans une liste thématique devrait aussi être dans `ldl_tot.txt`.

3. **Nommer les titres** en format uniforme : `Titre (Réalisateur, Année)` pour faciliter l'intégration future du bot de chat.

4. **Sauvegarder les listes** : les fichiers `ldl/*.txt` sont versionnés sur git (les URLs BTFS ne contiennent pas de données sensibles).
