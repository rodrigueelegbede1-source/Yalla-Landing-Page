-- 20260916008000_hook_acces_auth_admin.sql
--
-- Laisse le service d'authentification lire `utilisateurs`.
--
-- SYMPTÔME OBSERVÉ AU PREMIER DÉPLOIEMENT : toute connexion échouait en
-- HTTP 500, avec `Error running hook URI: pg-functions://postgres/public/
-- custom_access_token_hook`. Le hook, lui, rendait des claims parfaitement
-- corrects quand on l'appelait à la main en tant que `postgres`.
--
-- CAUSE : le hook n'est pas exécuté par `postgres` mais par `supabase_auth_admin`,
-- un rôle distinct. Or la migration des périmètres a activé RLS sur
-- `utilisateurs`, et les deux seules politiques posées visent `authenticated`.
-- Le service d'authentification, qui n'est ni `authenticated` ni propriétaire,
-- se retrouvait donc sans aucune politique applicable.
--
-- Le piège est que ce rôle avait bien le GRANT SELECT : le droit de table était
-- accordé, mais RLS filtrait ensuite tout. Il faut les deux, et c'est
-- précisément ce que documente Supabase pour un hook qui lit une table protégée.
--
-- Conséquence à retenir : **activer RLS sur une table que lit un hook casse
-- l'authentification entière**, et le message d'erreur ne dit rien de la cause.

-- Le hook a besoin de lire la ligne de l'utilisateur qui se connecte, avant
-- même qu'une identité existe. Aucune condition n'est donc possible, mais le
-- périmètre reste minimal : ce rôle est interne à Supabase, il n'est accessible
-- ni à l'application ni à un visiteur.
CREATE POLICY auth_admin_lit_utilisateurs ON utilisateurs
  AS PERMISSIVE FOR SELECT
  TO supabase_auth_admin
  USING (true);

COMMENT ON POLICY auth_admin_lit_utilisateurs ON utilisateurs IS
  'Sans cette politique, le hook d''émission de jeton ne peut pas lire le rôle et toute connexion échoue en 500.';
