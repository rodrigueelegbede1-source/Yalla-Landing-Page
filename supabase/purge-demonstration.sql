-- purge-demonstration.sql
--
-- Vide le projet Supabase de ses données de démonstration, avant de recenser de
-- vraies boutiques.
--
-- CE N'EST PAS UNE MIGRATION. Le fichier vit délibérément hors de
-- `migrations/`, pour deux raisons : il efface des données au lieu de faire
-- évoluer un schéma, et il ne doit surtout pas être rejoué automatiquement par
-- `supabase db push`. On l'exécute à la main, une fois, en connaissance de cause.
--
--   psql "$CONNEXION" -f supabase/purge-demonstration.sql
--
-- CE QU'IL EFFACE : tout le contenu métier. Les boutiques, les comptes, les
-- fabricants, les produits, les ruptures, les livraisons, les ventes.
--
-- CE QU'IL CONSERVE :
--   * le schéma, les fonctions, les politiques RLS et les tâches planifiées ;
--   * `categories_produit`, qui est une table de référence posée par la
--     migration du catalogue, pas une donnée de démonstration.
--
-- CE QU'IL NE PEUT PAS FAIRE. Les comptes de connexion vivent dans `auth.users`,
-- qui appartient à Supabase. `ON DELETE SET NULL` sur `utilisateurs.auth_user_id`
-- fait que supprimer une ligne `utilisateurs` laisse le compte de connexion
-- orphelin : il continuerait d'exister, et de permettre une connexion à un
-- compte sans rôle. La suppression des comptes est donc faite explicitement
-- ci-dessous, en dernier.
--
-- AVANT DE L'EXÉCUTER, faites une sauvegarde. Elle tient en une commande :
--
--   pg_dump "$CONNEXION" --data-only --schema=public --schema=auth \
--     -f sauvegarde-avant-purge.sql

BEGIN;

-- L'ordre suit les dépendances, des feuilles vers les racines. `TRUNCATE ...
-- CASCADE` serait plus court mais emporterait silencieusement des tables non
-- listées ici, y compris celles qu'une migration future ajouterait. Un DELETE
-- explicite par table rend visible ce qui disparaît.

-- 1. Les traces d'activité
DELETE FROM lignes_vente;
DELETE FROM ventes;
DELETE FROM positions_livreurs;
DELETE FROM livraisons;
DELETE FROM ruptures;
DELETE FROM stocks;
DELETE FROM transactions;

-- 2. Les sondages et notifications
DELETE FROM sondage_reponses;
DELETE FROM sondage_options;
DELETE FROM notifications;

-- 3. Le réseau
DELETE FROM attributions_reseau;
DELETE FROM produits;

-- 4. Les acteurs. `livreurs` avant `distributeurs` : la clé étrangère est en
-- ON DELETE RESTRICT, un distributeur qui a encore un livreur ne se supprime pas.
DELETE FROM livreurs;
DELETE FROM distributeurs;
DELETE FROM points_de_vente;
DELETE FROM agents_recenseurs;
DELETE FROM fabricants;
DELETE FROM utilisateurs;

-- 5. Les comptes de connexion.
--
-- Supabase gère lui-même les tables liées d'`auth` (sessions, identités,
-- jetons de rafraîchissement) par des clés étrangères en cascade depuis
-- `auth.users`. Supprimer l'utilisateur suffit donc.
--
-- La condition est délibérément large : à ce stade, `utilisateurs` est vide,
-- donc tout compte restant est orphelin par construction. Si vous exécutez ce
-- fichier partiellement, relisez cette instruction avant de la lancer.
DELETE FROM auth.users;

-- `categories_produit` n'est PAS effacée : c'est une table de référence.
-- Vérification, qui échoue bruyamment si quelqu'un l'a vidée par ailleurs.
DO $bloc$
BEGIN
  IF (SELECT count(*) FROM categories_produit) = 0 THEN
    RAISE EXCEPTION 'categories_produit est vide : la table de référence a été perdue, rejouez la migration du catalogue';
  END IF;
END;
$bloc$;

COMMIT;

-- Contrôle final. Toutes les lignes doivent être à zéro sauf les catégories.
SELECT 'utilisateurs' AS table_, count(*) FROM utilisateurs
UNION ALL SELECT 'auth.users',          count(*) FROM auth.users
UNION ALL SELECT 'points_de_vente',     count(*) FROM points_de_vente
UNION ALL SELECT 'distributeurs',       count(*) FROM distributeurs
UNION ALL SELECT 'livreurs',            count(*) FROM livreurs
UNION ALL SELECT 'fabricants',          count(*) FROM fabricants
UNION ALL SELECT 'produits',            count(*) FROM produits
UNION ALL SELECT 'ruptures',            count(*) FROM ruptures
UNION ALL SELECT 'livraisons',          count(*) FROM livraisons
UNION ALL SELECT 'ventes',              count(*) FROM ventes
UNION ALL SELECT 'stocks',              count(*) FROM stocks
UNION ALL SELECT 'attributions_reseau', count(*) FROM attributions_reseau
UNION ALL SELECT 'categories_produit (conservée)', count(*) FROM categories_produit
ORDER BY 1;
