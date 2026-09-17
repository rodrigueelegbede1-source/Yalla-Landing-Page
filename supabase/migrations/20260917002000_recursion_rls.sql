-- 20260917002000_recursion_rls.sql
--
-- Corrige une récursion infinie introduite par la migration précédente.
--
-- SYMPTÔME, constaté au premier lancement sur un téléphone :
--
--     infinite recursion detected in policy for relation "points_de_vente"
--     (SQLSTATE 42P17)
--
-- et PLUS AUCUNE lecture de `points_de_vente` ne passait, pour aucun rôle. Pas
-- seulement pour le distributeur visé par la politique fautive : les politiques
-- PERMISSIVE sont évaluées ensemble et combinées par OU, donc une seule qui
-- boucle fait tomber toute la table. L'agent recenseur, qui n'a rien à voir avec
-- cette politique, obtenait l'erreur en affichant simplement sa liste.
--
-- CAUSE : `pdv_commune_du_distributeur` est une politique SUR `points_de_vente`
-- dont la condition fait un `SELECT` SUR `points_de_vente`. PostgreSQL applique
-- alors les politiques de la table à cette sous-requête, ce qui rappelle la même
-- politique, indéfiniment.
--
-- CORRECTION : sortir la sous-requête dans une fonction `SECURITY DEFINER`.
-- Elle s'exécute avec les droits de son propriétaire, donc hors RLS, et la
-- boucle est rompue. C'est exactement ce que font déjà
-- `distributeur_voit_rupture` et `distributeur_dessert_point_de_vente` : la
-- règle implicite du fichier des périmètres était de ne jamais interroger depuis
-- une politique la table qu'elle protège, et je l'ai enfreinte.
--
-- LEÇON RETENUE, écrite ici pour la prochaine fois : cette faute ne se voit pas
-- en local. Le harnais vérifie que les politiques EXISTENT, pas qu'elles
-- s'exécutent, puisque personne n'y a d'identité. Elle n'est apparue qu'en
-- lançant l'application sur un appareil, contre la vraie base. Une politique
-- qui lit sa propre table doit être traitée comme fausse par défaut.

-- ── 1. Les communes où un distributeur opère déjà ───────────────────────────
--
-- `STABLE` et non `VOLATILE` : le planificateur peut alors n'appeler la fonction
-- qu'une fois par requête au lieu d'une fois par ligne. Sur une table de
-- plusieurs milliers de boutiques, la différence n'est pas cosmétique.
CREATE OR REPLACE FUNCTION communes_du_distributeur(p_distributeur_id UUID)
RETURNS TEXT[]
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT COALESCE(array_agg(DISTINCT pdv.commune), ARRAY[]::TEXT[])
    FROM attributions_reseau ar
    JOIN points_de_vente pdv ON pdv.id = ar.point_de_vente_id
   WHERE ar.distributeur_id = p_distributeur_id;
$fn$;

COMMENT ON FUNCTION communes_du_distributeur IS
  'SECURITY DEFINER par nécessité : appelée depuis une politique de points_de_vente, elle ne peut pas passer par RLS sans boucler.';

DROP POLICY IF EXISTS pdv_commune_du_distributeur ON points_de_vente;

CREATE POLICY pdv_commune_du_distributeur ON points_de_vente FOR SELECT TO authenticated
  USING (
    auth_role() = 'distributeur'
    AND statut = 'actif'
    AND commune = ANY (communes_du_distributeur(auth_id_metier()))
  );

-- ── 2. Les deux autres politiques ajoutées hier ─────────────────────────────
--
-- Elles ne bouclaient pas sur elles-mêmes, mais elles lisaient depuis une
-- politique de `utilisateurs` des tables (`points_de_vente`, `livraisons`)
-- elles-mêmes protégées, dont les politiques peuvent à leur tour lire
-- `utilisateurs`. Le chemin est plus long, le résultat serait le même.
--
-- Elles passent donc par des fonctions `SECURITY DEFINER`, comme le reste du
-- fichier des périmètres. Le périmètre lui-même ne change pas d'un iota.

CREATE OR REPLACE FUNCTION est_livreur_du_distributeur(p_utilisateur_id UUID, p_distributeur_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM livreurs l
     WHERE l.utilisateur_id = p_utilisateur_id
       AND l.distributeur_id = p_distributeur_id
  );
$fn$;

CREATE OR REPLACE FUNCTION est_gerant_en_course(p_utilisateur_id UUID, p_livreur_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT EXISTS (
    SELECT 1
      FROM points_de_vente pdv
      JOIN ruptures r   ON r.point_de_vente_id = pdv.id
      JOIN livraisons lv ON lv.rupture_id = r.id
     WHERE pdv.utilisateur_id = p_utilisateur_id
       AND lv.livreur_id = p_livreur_id
       AND lv.statut = 'en_cours'
  );
$fn$;

CREATE OR REPLACE FUNCTION est_gerant_recense_par(p_utilisateur_id UUID, p_agent_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM points_de_vente pdv
     WHERE pdv.utilisateur_id = p_utilisateur_id
       AND pdv.agent_recenseur_id = p_agent_id
  );
$fn$;

DROP POLICY IF EXISTS utilisateurs_livreurs_de_ma_flotte ON utilisateurs;
CREATE POLICY utilisateurs_livreurs_de_ma_flotte ON utilisateurs FOR SELECT TO authenticated
  USING (
    auth_role() = 'distributeur'
    AND est_livreur_du_distributeur(utilisateurs.id, auth_id_metier())
  );

DROP POLICY IF EXISTS utilisateurs_gerant_en_course ON utilisateurs;
CREATE POLICY utilisateurs_gerant_en_course ON utilisateurs FOR SELECT TO authenticated
  USING (
    auth_role() = 'livreur'
    AND est_gerant_en_course(utilisateurs.id, auth_id_metier())
  );

DROP POLICY IF EXISTS utilisateurs_gerants_recenses ON utilisateurs;
CREATE POLICY utilisateurs_gerants_recenses ON utilisateurs FOR SELECT TO authenticated
  USING (
    auth_role() = 'agent_recenseur'
    AND est_gerant_recense_par(utilisateurs.id, auth_id_metier())
  );

-- ── 3. Droits ───────────────────────────────────────────────────────────────
--
-- PAS DE REVOKE ICI, et c'est délibéré. Une expression de politique s'évalue
-- sous l'identité qui interroge, pas sous celle du propriétaire de la table :
-- retirer `EXECUTE` à `authenticated` rendrait les quatre fonctions
-- inappelables depuis les politiques qui en dépendent, et toutes les lectures
-- concernées échoueraient en « permission denied ». C'est la même raison qui
-- fait que les fonctions d'aide du fichier des périmètres
-- (`distributeur_voit_rupture`, `est_admin`, ...) gardent le droit `EXECUTE`
-- par défaut.
--
-- CONTREPARTIE ASSUMÉE : chacune prend une identité en paramètre, donc un
-- client authentifié peut les appeler avec une identité qui n'est pas la
-- sienne. Ce qu'il y gagnerait est volontairement dérisoire : un booléen
-- d'appartenance, ou une liste de noms de communes. Aucune ne rend une donnée
-- commerciale, et c'est le critère qui a présidé à leur découpage. Toute
-- fonction d'aide future doit respecter la même limite.
GRANT EXECUTE ON FUNCTION communes_du_distributeur, est_livreur_du_distributeur,
                          est_gerant_en_course, est_gerant_recense_par
  TO authenticated;
