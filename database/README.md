# Base de données Yalla — schéma PostgreSQL + PostGIS

Ce dossier contient le schéma complet, prêt à exécuter, qui correspond au
modèle de données défini dans `Yalla_Modele_de_donnees.md` et aux décisions
prises depuis (historique de positions, déclenchement automatique de
rupture, produits hors catalogue).

## Prérequis

- PostgreSQL 14+ avec l'extension **PostGIS** disponible (à vérifier sur
  l'offre managée NindoHost — sinon l'installer manuellement sur le serveur).
- `psql` en ligne de commande, ou un client équivalent.

## Structure

```
database/
  migrations/
    001_extensions_et_enums.sql
    002_utilisateurs_et_roles.sql
    003_points_de_vente_et_positions.sql
    004_catalogue_et_attribution.sql
    005_ruptures_et_livraisons.sql
    006_caisse_enregistreuse.sql
    007_notifications_sondages_transactions.sql
    008_vues_tableaux_de_bord.sql
    009_maintenance.sql
  seed/
    seed_dev.sql
```

Les fichiers sont numérotés dans l'ordre où ils doivent être exécutés — chacun
dépend des tables créées par les précédents (clés étrangères).

## Exécuter les migrations

```bash
createdb yalla_dev

for f in database/migrations/*.sql; do
  echo "→ $f"
  psql -d yalla_dev -v ON_ERROR_STOP=1 -f "$f"
done
```

## Charger le jeu de données de démonstration (dev uniquement)

```bash
psql -d yalla_dev -f database/seed/seed_dev.sql
```

Ce script recrée les entités déjà utilisées dans les 6 maquettes cliquables
(Ivoire Boissons, Superette Akwaba, Koffi A., etc.) et insère une vente qui
vide volontairement un stock, pour vérifier que le trigger de rupture
automatique fonctionne :

```sql
SELECT * FROM ruptures;              -- 1 ligne, signalement_automatique = true
SELECT * FROM v_ruptures_ouvertes;   -- vue utilisée par les dashboards
```

## Ce que couvre déjà ce schéma

- **Rôles et comptes** : `utilisateurs` + une table par rôle (`fabricants`,
  `livreurs`, `agents_recenseurs`) — un point de vente n'a volontairement pas
  de compte utilisateur dédié dans ce schéma v1 (à ajouter si l'authentification
  par point de vente doit être individualisée plutôt que par gérant).
- **Géolocalisation** : colonnes `GEOGRAPHY(POINT, 4326)` + index `GIST` sur
  `points_de_vente`, `livreurs` et `positions_livreurs`, pour des requêtes de
  proximité natives (`ORDER BY position <-> ...`, voir l'exemple dans
  `008_vues_tableaux_de_bord.sql`).
- **Historique de positions** avec synchronisation automatique de la dernière
  position connue sur `livreurs` (trigger), et fonction de purge à 30 jours
  (`009_maintenance.sql`) à planifier via `pg_cron` ou un job NestJS.
- **Caisse enregistreuse** : `stocks`, `ventes`, `lignes_vente`, avec gestion
  des produits hors catalogue (`produit_libre_nom`), et le trigger métier
  central du projet : une vente qui vide un stock crée automatiquement une
  rupture.
- **Vues prêtes pour les dashboards** déjà maquettés : CA par fabricant, CA
  par livreur, ruptures ouvertes.

## Ce qui reste à faire côté application (hors schéma)

- Générer les migrations dans le format attendu par l'ORM retenu côté NestJS
  (TypeORM ou Prisma) — ce dossier peut servir de source de vérité SQL à
  reproduire, ou être exécuté tel quel puis introspecté (`prisma db pull`).
- Brancher l'intégration CinetPay pour remplir `transactions.reference_cinetpay`
  et faire transiter `statut` de `en_attente` à `confirmee`/`echouee` via
  webhook.
- Ajouter la logique d'envoi réel des notifications (FCM) déclenchée à
  l'insertion d'une ligne dans `notifications`.
