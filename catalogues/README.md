# Catalogues fabricants

Les listes de produits importées par `scripts/creer-fabricant.sh`, conservées
telles qu'elles ont été jouées.

**Pourquoi les garder.** Un catalogue rejoué n'est pas idempotent : la
contrainte d'unicité sur `(fabricant_id, reference)` fait échouer un second
import du même fichier. Garder le fichier permet de savoir ce qui a été
inscrit, de le comparer à ce que le fabricant fournira plus tard, et de
reconstituer la base après une purge sans recommencer la saisie.

**Ce que ces fichiers ne sont pas :** la nomenclature officielle du fabricant.
Les références sont générées quand il ne la fournit pas, et n'ont de valeur que
pour Yalla. Voir l'en-tête de `scripts/creer-fabricant.sh`.

| Fichier | Fabricant | Notes |
|---|---|---|
| `2026-09-17_sdtm-ci.csv` | SDTM-CI (Carré d'Or) | 30 unités de vente boutique, relevées sur la boutique Jumia officielle. Marques propres uniquement : Alyssa, Maman, La Rizière, Uncle Sam, Laity, Darci, Madar, Get, Olinda, Toplait. Coca-Cola, Fanta et Sprite volontairement exclues, ce sont des marques tierces distribuées |
