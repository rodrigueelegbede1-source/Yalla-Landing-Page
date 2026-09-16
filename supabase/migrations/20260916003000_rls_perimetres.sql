-- 20260916003000_rls_perimetres.sql
--
-- Les périmètres par rôle passent du code applicatif à la base.
--
-- POURQUOI CETTE MIGRATION EXISTE
--
-- L'API NestJS portait les périmètres dans un `RolesGuard` qui ne vérifiait que
-- « ce rôle a-t-il le droit d'appeler cette route ». Il ne vérifiait jamais que
-- la ressource visée appartenait bien à l'appelant. La relecture complète du
-- backend a trouvé sept endroits où cela ouvrait une fuite réelle :
--
--   * un fabricant pouvait lire le réseau et le chiffre d'affaires d'un concurrent
--   * un fabricant pouvait injecter des produits dans le catalogue d'un concurrent
--   * un point de vente pouvait en retirer un autre du réseau
--   * un point de vente pouvait signaler une rupture au nom d'un autre
--   * un point de vente pouvait lire le stock et encaisser sur la caisse d'un autre
--   * un livreur pouvait mettre un autre livreur en ligne ou hors ligne
--   * n'importe quel client WebSocket pouvait rejoindre la room d'un fabricant
--
-- Ces fuites avaient toutes la même cause : l'identifiant venait de l'URL ou du
-- corps de la requête, jamais du jeton. En déplaçant la règle dans la base, elle
-- n'est plus contournable, quel que soit le client. C'est le gain principal du
-- passage à Supabase, bien avant l'économie d'hébergement.
--
-- PRINCIPE : tout est refusé par défaut. Chaque politique n'ouvre que ce qui est
-- strictement nécessaire au rôle, en lisant l'identité dans le jeton via
-- `auth_role()` et `auth_id_metier()` (migration précédente).

-- ── 1. Fonctions de décision ───────────────────────────────────────────────
--
-- SECURITY DEFINER assumé : ces fonctions doivent lire `attributions_reseau`,
-- `produits` et `points_de_vente` sans être elles-mêmes soumises aux politiques,
-- sinon on obtient une récursion infinie. Elles ne rendent qu'un booléen ou un
-- identifiant, jamais de données : le périmètre d'exposition est nul.

CREATE OR REPLACE FUNCTION est_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE AS $fn$
  SELECT auth_role() = 'administrateur';
$fn$;

-- Le distributeur dont dépend le livreur courant.
CREATE OR REPLACE FUNCTION distributeur_du_livreur(p_livreur_id UUID)
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT distributeur_id FROM livreurs WHERE id = p_livreur_id;
$fn$;

-- Le distributeur courant, qu'on soit connecté comme distributeur ou comme
-- livreur rattaché à lui. Toute la visibilité des ruptures passe par là.
CREATE OR REPLACE FUNCTION distributeur_courant()
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT CASE auth_role()
    WHEN 'distributeur' THEN auth_id_metier()
    WHEN 'livreur'      THEN distributeur_du_livreur(auth_id_metier())
    ELSE NULL
  END;
$fn$;

-- Le cœur du contrôle d'accès aux ruptures : les deux cercles de la règle
-- d'escalade, exprimés une seule fois. C'est la même logique que la vue
-- `v_acces_rupture_distributeur`, mais sous forme de prédicat pour éviter que
-- les politiques ne dépendent d'une vue, qui serait elle-même soumise à RLS.
CREATE OR REPLACE FUNCTION distributeur_voit_rupture(p_rupture_id UUID, p_distributeur_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT EXISTS (
    -- Cercle attribué : la rupture lui est adressée.
    SELECT 1 FROM ruptures r
     WHERE r.id = p_rupture_id
       AND r.distributeur_id = p_distributeur_id
    UNION ALL
    -- Cercle élargi : après escalade, même marque et même commune.
    SELECT 1
      FROM ruptures r
      JOIN produits p           ON p.id = r.produit_id
      JOIN points_de_vente pdv  ON pdv.id = r.point_de_vente_id
      JOIN attributions_reseau ar ON ar.fabricant_id = p.fabricant_id
      JOIN points_de_vente autre  ON autre.id = ar.point_de_vente_id
                                 AND autre.commune = pdv.commune
     WHERE r.id = p_rupture_id
       AND r.escaladee_le IS NOT NULL
       AND ar.distributeur_id = p_distributeur_id
  );
$fn$;

COMMENT ON FUNCTION distributeur_voit_rupture IS
  'Règle des deux cercles. Ne jamais la dupliquer ailleurs : elle est la définition unique du périmètre d''une rupture.';

-- Un distributeur dessert-il ce point de vente ?
CREATE OR REPLACE FUNCTION distributeur_dessert_point_de_vente(p_pdv_id UUID, p_distributeur_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM attributions_reseau
     WHERE point_de_vente_id = p_pdv_id
       AND distributeur_id   = p_distributeur_id
  );
$fn$;

-- ── 2. Activation de RLS sur toutes les tables ─────────────────────────────
--
-- Sans politique, RLS activé = tout refusé. Les tables hors périmètre du MVP
-- (notifications, sondages, transactions, agents recenseurs) restent donc
-- volontairement fermées : rien ne peut fuir par une table qu'on n'a pas encore
-- traitée. C'est l'inverse exact du comportement du RolesGuard, qui laissait
-- passer toute route sans décorateur @Roles.

ALTER TABLE utilisateurs         ENABLE ROW LEVEL SECURITY;
ALTER TABLE agents_recenseurs    ENABLE ROW LEVEL SECURITY;
ALTER TABLE fabricants           ENABLE ROW LEVEL SECURITY;
ALTER TABLE distributeurs        ENABLE ROW LEVEL SECURITY;
ALTER TABLE livreurs             ENABLE ROW LEVEL SECURITY;
ALTER TABLE points_de_vente      ENABLE ROW LEVEL SECURITY;
ALTER TABLE positions_livreurs   ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories_produit   ENABLE ROW LEVEL SECURITY;
ALTER TABLE produits             ENABLE ROW LEVEL SECURITY;
ALTER TABLE attributions_reseau  ENABLE ROW LEVEL SECURITY;
ALTER TABLE ruptures             ENABLE ROW LEVEL SECURITY;
ALTER TABLE livraisons           ENABLE ROW LEVEL SECURITY;
ALTER TABLE stocks               ENABLE ROW LEVEL SECURITY;
ALTER TABLE ventes               ENABLE ROW LEVEL SECURITY;
ALTER TABLE lignes_vente         ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications        ENABLE ROW LEVEL SECURITY;
ALTER TABLE sondage_options      ENABLE ROW LEVEL SECURITY;
ALTER TABLE sondage_reponses     ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions         ENABLE ROW LEVEL SECURITY;

-- ── 3. Identités ───────────────────────────────────────────────────────────

CREATE POLICY utilisateurs_soi_meme ON utilisateurs FOR SELECT TO authenticated
  USING (auth_user_id = auth.uid() OR est_admin());

CREATE POLICY utilisateurs_maj_soi_meme ON utilisateurs FOR UPDATE TO authenticated
  USING (auth_user_id = auth.uid())
  WITH CHECK (auth_user_id = auth.uid());

-- ── 4. Le point de vente ───────────────────────────────────────────────────
--
-- Trois publics le voient, pour des raisons différentes : lui-même, le
-- distributeur qui le dessert, et le livreur qui doit s'y rendre. Le livreur
-- n'y a accès que le temps d'une rupture qui le concerne.

CREATE POLICY pdv_lui_meme ON points_de_vente FOR SELECT TO authenticated
  USING (auth_role() = 'point_de_vente' AND id = auth_id_metier());

CREATE POLICY pdv_son_distributeur ON points_de_vente FOR SELECT TO authenticated
  USING (
    distributeur_courant() IS NOT NULL
    AND distributeur_dessert_point_de_vente(id, distributeur_courant())
  );

CREATE POLICY pdv_livreur_en_course ON points_de_vente FOR SELECT TO authenticated
  USING (
    auth_role() = 'livreur'
    AND EXISTS (
      SELECT 1 FROM ruptures r
       WHERE r.point_de_vente_id = points_de_vente.id
         AND r.statut IN ('signalee', 'prise_en_charge')
         AND distributeur_voit_rupture(r.id, distributeur_courant())
    )
  );

CREATE POLICY pdv_admin ON points_de_vente FOR ALL TO authenticated
  USING (est_admin()) WITH CHECK (est_admin());

-- Le point de vente met à jour sa propre fiche, jamais celle d'un autre.
-- C'est précisément la faille de `PATCH /points-de-vente/:id/retirer`.
CREATE POLICY pdv_maj_lui_meme ON points_de_vente FOR UPDATE TO authenticated
  USING (auth_role() = 'point_de_vente' AND id = auth_id_metier())
  WITH CHECK (auth_role() = 'point_de_vente' AND id = auth_id_metier());

-- ── 5. La caisse est privée. C'est une promesse commerciale. ───────────────
--
-- `stocks`, `ventes` et `lignes_vente` ne sont lisibles que par le point de
-- vente qui les a produits. Ni distributeur, ni fabricant, ni livreur. Un
-- boutiquier doit pouvoir utiliser la caisse gratuite sans craindre que son
-- chiffre d'affaires remonte à ses fournisseurs : c'est ce qui rend l'outil
-- acceptable, donc c'est ce qui fait marcher le signalement automatique.

CREATE POLICY stocks_prives ON stocks FOR ALL TO authenticated
  USING (auth_role() = 'point_de_vente' AND point_de_vente_id = auth_id_metier())
  WITH CHECK (auth_role() = 'point_de_vente' AND point_de_vente_id = auth_id_metier());

CREATE POLICY ventes_privees ON ventes FOR ALL TO authenticated
  USING (auth_role() = 'point_de_vente' AND point_de_vente_id = auth_id_metier())
  WITH CHECK (auth_role() = 'point_de_vente' AND point_de_vente_id = auth_id_metier());

CREATE POLICY lignes_vente_privees ON lignes_vente FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM ventes v
     WHERE v.id = lignes_vente.vente_id
       AND auth_role() = 'point_de_vente'
       AND v.point_de_vente_id = auth_id_metier()
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM ventes v
     WHERE v.id = lignes_vente.vente_id
       AND auth_role() = 'point_de_vente'
       AND v.point_de_vente_id = auth_id_metier()
  ));

-- ── 6. Les ruptures ────────────────────────────────────────────────────────

CREATE POLICY ruptures_pdv_siennes ON ruptures FOR SELECT TO authenticated
  USING (auth_role() = 'point_de_vente' AND point_de_vente_id = auth_id_metier());

-- Le point de vente signale pour lui-même, et pour personne d'autre.
CREATE POLICY ruptures_pdv_signale ON ruptures FOR INSERT TO authenticated
  WITH CHECK (auth_role() = 'point_de_vente' AND point_de_vente_id = auth_id_metier());

CREATE POLICY ruptures_distributeur ON ruptures FOR SELECT TO authenticated
  USING (
    distributeur_courant() IS NOT NULL
    AND distributeur_voit_rupture(id, distributeur_courant())
  );

CREATE POLICY ruptures_admin ON ruptures FOR ALL TO authenticated
  USING (est_admin()) WITH CHECK (est_admin());

-- Aucune politique UPDATE : la prise en charge passe exclusivement par la
-- fonction `prendre_rupture()` de la migration suivante, qui porte le verrou
-- de concurrence. Laisser un UPDATE libre rouvrirait la course entre livreurs.

-- ── 7. Livraisons et flotte ────────────────────────────────────────────────

CREATE POLICY livraisons_livreur ON livraisons FOR SELECT TO authenticated
  USING (auth_role() = 'livreur' AND livreur_id = auth_id_metier());

CREATE POLICY livraisons_distributeur ON livraisons FOR SELECT TO authenticated
  USING (
    auth_role() = 'distributeur'
    AND EXISTS (SELECT 1 FROM livreurs l
                 WHERE l.id = livraisons.livreur_id
                   AND l.distributeur_id = auth_id_metier())
  );

CREATE POLICY livraisons_pdv ON livraisons FOR SELECT TO authenticated
  USING (auth_role() = 'point_de_vente' AND point_de_vente_id = auth_id_metier());

CREATE POLICY livraisons_admin ON livraisons FOR ALL TO authenticated
  USING (est_admin()) WITH CHECK (est_admin());

CREATE POLICY livreurs_soi_meme ON livreurs FOR SELECT TO authenticated
  USING (auth_role() = 'livreur' AND id = auth_id_metier());

CREATE POLICY livreurs_sa_flotte ON livreurs FOR SELECT TO authenticated
  USING (auth_role() = 'distributeur' AND distributeur_id = auth_id_metier());

-- Un livreur ne change que son propre état. C'est la faille de
-- `PATCH /livreurs/:id/en-ligne`, qui prenait l'identifiant dans l'URL.
CREATE POLICY livreurs_maj_soi_meme ON livreurs FOR UPDATE TO authenticated
  USING (auth_role() = 'livreur' AND id = auth_id_metier())
  WITH CHECK (auth_role() = 'livreur' AND id = auth_id_metier());

CREATE POLICY livreurs_admin ON livreurs FOR ALL TO authenticated
  USING (est_admin()) WITH CHECK (est_admin());

CREATE POLICY positions_livreur_ecrit ON positions_livreurs FOR INSERT TO authenticated
  WITH CHECK (auth_role() = 'livreur' AND livreur_id = auth_id_metier());

CREATE POLICY positions_lecture ON positions_livreurs FOR SELECT TO authenticated
  USING (
    (auth_role() = 'livreur' AND livreur_id = auth_id_metier())
    OR (auth_role() = 'distributeur'
        AND EXISTS (SELECT 1 FROM livreurs l
                     WHERE l.id = positions_livreurs.livreur_id
                       AND l.distributeur_id = auth_id_metier()))
    OR est_admin()
  );

-- ── 8. Catalogue et réseau ─────────────────────────────────────────────────
--
-- Le catalogue des fabricants est public à l'intérieur de la plateforme : un
-- boutiquier doit pouvoir chercher un produit chez n'importe quelle marque, et
-- un livreur doit pouvoir lire la fiche du produit qu'il transporte. Ce qui est
-- confidentiel, ce ne sont pas les références, ce sont les ruptures et les ventes.

CREATE POLICY produits_lecture ON produits FOR SELECT TO authenticated USING (true);
CREATE POLICY categories_lecture ON categories_produit FOR SELECT TO authenticated USING (true);
CREATE POLICY fabricants_lecture ON fabricants FOR SELECT TO authenticated USING (true);

CREATE POLICY produits_admin ON produits FOR ALL TO authenticated
  USING (est_admin()) WITH CHECK (est_admin());

-- Le distributeur voit les attributions qui le concernent, et elles seules :
-- savoir quelles boutiques un confrère dessert serait un renseignement commercial.
CREATE POLICY attributions_siennes ON attributions_reseau FOR SELECT TO authenticated
  USING (distributeur_courant() IS NOT NULL AND distributeur_id = distributeur_courant());

CREATE POLICY attributions_pdv ON attributions_reseau FOR SELECT TO authenticated
  USING (auth_role() = 'point_de_vente' AND point_de_vente_id = auth_id_metier());

CREATE POLICY attributions_admin ON attributions_reseau FOR ALL TO authenticated
  USING (est_admin()) WITH CHECK (est_admin());

CREATE POLICY distributeurs_soi_meme ON distributeurs FOR SELECT TO authenticated
  USING (auth_role() = 'distributeur' AND id = auth_id_metier());

-- Un livreur doit pouvoir lire la fiche de son propre distributeur.
CREATE POLICY distributeurs_du_livreur ON distributeurs FOR SELECT TO authenticated
  USING (auth_role() = 'livreur' AND id = distributeur_courant());

CREATE POLICY distributeurs_admin ON distributeurs FOR ALL TO authenticated
  USING (est_admin()) WITH CHECK (est_admin());

-- ── 9. Les vues doivent respecter RLS ──────────────────────────────────────
--
-- PIÈGE MAJEUR : par défaut une vue PostgreSQL s'exécute avec les droits de son
-- propriétaire, ce qui CONTOURNE silencieusement toutes les politiques
-- ci-dessus. Une requête sur `v_ruptures_ouvertes` rendrait alors le réseau
-- entier, politiques ou pas. `security_invoker` rétablit les droits de l'appelant.

ALTER VIEW v_ruptures_ouvertes                   SET (security_invoker = on);
ALTER VIEW v_acces_rupture_distributeur          SET (security_invoker = on);
ALTER VIEW v_chiffre_affaires_par_fabricant      SET (security_invoker = on);
ALTER VIEW v_chiffre_affaires_par_livreur        SET (security_invoker = on);
ALTER VIEW v_chiffre_affaires_genere_par_fabricant SET (security_invoker = on);
ALTER VIEW v_taux_de_service_par_fabricant       SET (security_invoker = on);
