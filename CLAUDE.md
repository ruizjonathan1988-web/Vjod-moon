# VJOD — règles du dépôt

- Réponses, commits, descriptions de PR et textes de l'appli en français.
- Rien n'est poussé sur `main`, `matv`, `perso` ou `perso-wip` sans l'accord écrit de Xavier. Jamais de force-push ni de suppression de branche.
- Chaque changement sur sa branche (depuis `matv`), PR vers `matv`, tests ajoutés à la liste de `.github/workflows/perso-check.yml`, « Verif perso » verte avant toute fusion.

## Numéro de version (depuis VJOD 4.1)

Chaque mise à jour publiée porte un numéro qui suit : 4.1, 4.2, 4.3…

1. Ajouter une entrée **en tête** de `vjodReleases` dans `lib/util/vjod_changes.dart` avec le numéro suivant et les nouveautés (une ligne par changement, en français simple).
2. Mettre le même numéro dans `VjodBuild.version` (`lib/util/vjod_build.dart`). Un test vérifie que les deux concordent.
3. Titre de la PR : « VJOD 4.x — … ».

La build (`perso-apk.yml`) écrit le numéro et les nouveautés sur la release `perso-latest` : la fenêtre de mise à jour affiche « VJOD 4.x est disponible », l'appli montre « ce qui change » une fois après la mise à jour, et « À propos » liste les nouveautés.
