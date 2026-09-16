-- 20260916001050_valeurs_enum_distributeur.sql
--
-- Les trois valeurs d'énumération dont a besoin la migration suivante.
--
-- POURQUOI UN FICHIER À PART, et pourquoi il ne faut pas les y refusionner :
--
-- PostgreSQL interdit d'utiliser une valeur d'énumération dans la même
-- transaction que son ajout (SQLSTATE 55P04, « unsafe use of new value »).
--
-- Le piège est que cela dépend de qui applique la migration :
--
--   * `psql -f fichier.sql` valide chaque instruction séparément. Ajouter la
--     valeur puis s'en servir plus bas fonctionne, et le problème reste invisible.
--   * `supabase db push` enveloppe **chaque fichier dans une transaction unique**.
--     Le même fichier échoue alors, à mi-parcours, en laissant la base distante
--     dans un état intermédiaire.
--
-- C'est exactement ce qui s'est produit au premier déploiement : la vue
-- `v_taux_de_service_par_fabricant`, qui filtre sur `non_servie`, a fait échouer
-- la migration 011 sur Supabase alors qu'elle passait en local.
--
-- Toute nouvelle valeur d'énumération va donc dans son propre fichier, appliqué
-- avant celui qui l'utilise.

-- Le distributeur, sixième rôle.
ALTER TYPE role_utilisateur ADD VALUE IF NOT EXISTS 'distributeur';

-- Statut terminal d'une rupture que personne n'a prise. Sans lui, une rupture
-- abandonnée reste « ouverte » indéfiniment et le taux de service, qui est
-- l'indicateur vendu au fabricant, n'est pas calculable.
ALTER TYPE statut_rupture ADD VALUE IF NOT EXISTS 'non_servie';

-- Cible de diffusion pour les notifications adressées aux distributeurs.
ALTER TYPE cible_notification ADD VALUE IF NOT EXISTS 'distributeurs';
