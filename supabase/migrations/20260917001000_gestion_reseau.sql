-- 20260917001000_gestion_reseau.sql
--
-- Rend le réseau administrable depuis l'application, au lieu de l'être à la
-- main en SQL.
--
-- CE QUI MANQUAIT, et pourquoi c'est bloquant pour le pilote d'Abidjan :
--
--   * Créer un compte demandait deux `INSERT` et un appel à l'API
--     d'administration, tapés à la main. Autant dire que recenser trente
--     boutiques à Cocody était impossible sans moi devant un terminal.
--   * Un distributeur ne pouvait pas rattacher un livreur à sa flotte, donc la
--     seule action qui lui reste, « affecter », n'avait personne à qui affecter.
--   * Aucun distributeur ne pouvait déclarer quelle boutique il dessert pour
--     quelle marque. Or c'est `attributions_reseau.distributeur_id` qui décide
--     du destinataire d'une rupture. Sans lui, toute rupture part sans adresse
--     et n'existe qu'après escalade.
--
-- Le fil conducteur reste celui des périmètres : l'agent recense, le
-- distributeur revendique, et chacun ne touche que ce qui le concerne. Aucune
-- de ces fonctions ne prend une identité en paramètre, elles la lisent dans le
-- jeton.

-- ── 1. Un livreur peut être écarté sans être supprimé ───────────────────────
--
-- `livreurs.distributeur_id` est en ON DELETE RESTRICT et `livraisons` référence
-- le livreur : supprimer une ligne effacerait l'historique des courses, ou
-- échouerait. Un livreur qui quitte la flotte est donc désactivé, et ses
-- livraisons passées restent lisibles.
ALTER TABLE livreurs ADD COLUMN IF NOT EXISTS actif BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN livreurs.actif IS
  'Faux quand le distributeur l''a écarté de sa flotte. La ligne est conservée pour l''historique des livraisons.';

-- ── 2. Le distributeur voit le nom de ses livreurs ──────────────────────────
--
-- BOGUE CORRIGÉ ICI. `livreurs_sa_flotte` laissait bien le distributeur lire la
-- table `livreurs`, mais `utilisateurs_soi_meme` est la seule politique de
-- lecture sur `utilisateurs`. La jointure qui va chercher le nom ne rendait donc
-- rien, et la liste d'affectation affichait « Livreur » pour tout le monde.
-- Le symptôme est silencieux : PostgREST ne signale pas une ligne filtrée par
-- RLS, il la remplace par un nul.
CREATE POLICY utilisateurs_livreurs_de_ma_flotte ON utilisateurs FOR SELECT TO authenticated
  USING (
    auth_role() = 'distributeur'
    AND EXISTS (
      SELECT 1 FROM livreurs l
       WHERE l.utilisateur_id = utilisateurs.id
         AND l.distributeur_id = auth_id_metier()
    )
  );

-- Symétrique, et pour la même raison : le livreur affiche le nom du gérant de
-- la boutique où il livre, qui vit lui aussi dans `utilisateurs`.
CREATE POLICY utilisateurs_gerant_en_course ON utilisateurs FOR SELECT TO authenticated
  USING (
    auth_role() = 'livreur'
    AND EXISTS (
      SELECT 1 FROM points_de_vente pdv
        JOIN ruptures r ON r.point_de_vente_id = pdv.id
        JOIN livraisons lv ON lv.rupture_id = r.id
       WHERE pdv.utilisateur_id = utilisateurs.id
         AND lv.livreur_id = auth_id_metier()
         AND lv.statut = 'en_cours'
    )
  );

-- ── 3. L'agent recenseur ────────────────────────────────────────────────────
--
-- Il n'avait aucune politique, donc aucun accès : son rôle existait en base
-- mais il ne pouvait rien lire ni écrire. Il voit sa propre fiche et les
-- boutiques qu'il a lui-même recensées, rien d'autre. En particulier, il ne voit
-- ni les ventes, ni les stocks, ni les ruptures : recenser n'est pas surveiller.

CREATE POLICY agents_soi_meme ON agents_recenseurs FOR SELECT TO authenticated
  USING (
    utilisateur_id = auth_utilisateur_id() OR est_admin()
  );

CREATE POLICY agents_admin ON agents_recenseurs FOR ALL TO authenticated
  USING (est_admin()) WITH CHECK (est_admin());

CREATE POLICY pdv_recensees_par_moi ON points_de_vente FOR SELECT TO authenticated
  USING (
    auth_role() = 'agent_recenseur'
    AND agent_recenseur_id = auth_id_metier()
  );

CREATE POLICY utilisateurs_gerants_recenses ON utilisateurs FOR SELECT TO authenticated
  USING (
    auth_role() = 'agent_recenseur'
    AND EXISTS (
      SELECT 1 FROM points_de_vente pdv
       WHERE pdv.utilisateur_id = utilisateurs.id
         AND pdv.agent_recenseur_id = auth_id_metier()
    )
  );

-- Le distributeur a besoin de voir les boutiques de son secteur pour pouvoir en
-- revendiquer. `pdv_son_distributeur` ne montre que celles qu'il dessert déjà,
-- ce qui rend la revendication impossible : on ne peut pas choisir dans une
-- liste vide. Il voit donc aussi les boutiques actives de toute commune où il
-- opère déjà, et seulement leur fiche publique.
CREATE POLICY pdv_commune_du_distributeur ON points_de_vente FOR SELECT TO authenticated
  USING (
    auth_role() = 'distributeur'
    AND statut = 'actif'
    AND commune IN (
      SELECT pdv2.commune
        FROM attributions_reseau ar
        JOIN points_de_vente pdv2 ON pdv2.id = ar.point_de_vente_id
       WHERE ar.distributeur_id = auth_id_metier()
    )
  );

-- ── 4. Créer un compte, depuis l'application ────────────────────────────────
--
-- POURQUOI CETTE FONCTION NE CRÉE PAS LE COMPTE DE CONNEXION : créer un
-- utilisateur dans `auth.users` exige la clé `service_role`, qui contourne RLS
-- et ne doit jamais entrer dans un APK. La création se fait donc en deux temps,
-- et c'est la fonction Edge `creer-compte` qui les enchaîne :
--
--   1. elle crée le compte de connexion avec `service_role`, côté serveur ;
--   2. elle appelle CETTE fonction **avec le jeton de l'appelant**, si bien que
--      `auth_role()` rend le rôle réel de l'agent ou du distributeur, et que le
--      contrôle de périmètre ci-dessous s'applique pour de bon ;
--   3. si cette fonction refuse, elle supprime le compte qu'elle vient de créer.
--
-- Conséquence à ne pas perdre de vue : appelée avec `service_role`, cette
-- fonction refuserait tout, `auth_role()` étant alors nul. C'est voulu.
CREATE OR REPLACE FUNCTION creer_compte_metier(
  p_auth_user_id UUID,
  p_nom          TEXT,
  p_telephone    TEXT,
  p_role         role_utilisateur,
  p_details      JSONB DEFAULT '{}'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_createur  role_utilisateur := auth_role();
  v_createur_metier UUID       := auth_id_metier();
  v_tel       TEXT;
  v_u_id      UUID;
  v_id_metier UUID;
BEGIN
  IF v_createur IS NULL THEN
    RAISE EXCEPTION 'Authentification requise' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Qui a le droit de créer quoi. Le distributeur ne crée que des livreurs,
  -- l'agent ne crée que des boutiques et des distributeurs. Un agent ne peut
  -- donc pas se fabriquer un compte administrateur.
  IF NOT (
       v_createur = 'administrateur'
    OR (v_createur = 'agent_recenseur' AND p_role IN ('point_de_vente', 'distributeur'))
    OR (v_createur = 'distributeur'    AND p_role = 'livreur')
  ) THEN
    RAISE EXCEPTION 'Votre rôle ne permet pas de créer un compte « % »', p_role
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Treize chiffres, sans `+` : la forme que rend `normaliser_telephone`, et
  -- la même que produisent le Dart et la fonction Edge. Les trois doivent
  -- coïncider, sans quoi un compte se crée sous une adresse et se connecte sous
  -- une autre.
  v_tel := normaliser_telephone(p_telephone);
  IF v_tel IS NULL OR length(v_tel) <> 13 OR left(v_tel, 3) <> '225' THEN
    RAISE EXCEPTION 'Numéro de téléphone invalide : %', p_telephone
      USING ERRCODE = 'check_violation';
  END IF;

  IF EXISTS (SELECT 1 FROM utilisateurs WHERE telephone = v_tel) THEN
    RAISE EXCEPTION 'Ce numéro est déjà rattaché à un compte Yalla'
      USING ERRCODE = 'unique_violation';
  END IF;

  INSERT INTO utilisateurs (nom, telephone, role, auth_user_id)
  VALUES (trim(p_nom), v_tel, p_role, p_auth_user_id)
  RETURNING id INTO v_u_id;

  IF p_role = 'point_de_vente' THEN
    INSERT INTO points_de_vente (
      nom, type_activite, commune, ville, adresse, position,
      gerant_nom, telephone, statut, agent_recenseur_id, utilisateur_id
    )
    VALUES (
      trim(p_details->>'nom_boutique'),
      (p_details->>'type_activite')::type_activite,
      trim(p_details->>'commune'),
      COALESCE(NULLIF(trim(p_details->>'ville'), ''), 'Abidjan'),
      NULLIF(trim(COALESCE(p_details->>'adresse', '')), ''),
      ST_SetSRID(ST_MakePoint(
        (p_details->>'longitude')::DOUBLE PRECISION,
        (p_details->>'latitude')::DOUBLE PRECISION
      ), 4326)::GEOGRAPHY,
      trim(p_nom),
      v_tel,
      -- Le compte est remis en main propre au moment du recensement, la boutique
      -- est donc opérationnelle tout de suite. `en_attente_activation` servait à
      -- un parcours où le recensement précédait la remise des identifiants.
      'actif',
      CASE WHEN v_createur = 'agent_recenseur' THEN v_createur_metier ELSE NULL END,
      v_u_id
    )
    RETURNING id INTO v_id_metier;

  ELSIF p_role = 'distributeur' THEN
    INSERT INTO distributeurs (nom, telephone, utilisateur_id, fabricant_id, statut)
    VALUES (
      COALESCE(NULLIF(trim(COALESCE(p_details->>'nom_societe', '')), ''), trim(p_nom)),
      v_tel,
      v_u_id,
      NULLIF(p_details->>'fabricant_id', '')::UUID,
      'actif'
    )
    RETURNING id INTO v_id_metier;

  ELSIF p_role = 'livreur' THEN
    INSERT INTO livreurs (utilisateur_id, distributeur_id)
    VALUES (v_u_id, v_createur_metier)
    RETURNING id INTO v_id_metier;

  ELSIF p_role = 'agent_recenseur' THEN
    INSERT INTO agents_recenseurs (utilisateur_id, secteur)
    VALUES (v_u_id, COALESCE(NULLIF(trim(COALESCE(p_details->>'secteur', '')), ''), 'Abidjan'))
    RETURNING id INTO v_id_metier;
  END IF;

  RETURN jsonb_build_object(
    'utilisateur_id', v_u_id,
    'id_metier',      v_id_metier,
    'telephone',      v_tel,
    'role',           p_role
  );
END;
$fn$;

COMMENT ON FUNCTION creer_compte_metier IS
  'Crée la ligne métier d''un compte déjà présent dans auth.users. Appelée par la fonction Edge creer-compte, jamais directement par le client.';

-- ── 5. La flotte du distributeur ────────────────────────────────────────────

CREATE OR REPLACE FUNCTION ecarter_livreur(p_livreur_id UUID, p_actif BOOLEAN DEFAULT false)
RETURNS livreurs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_livreur livreurs;
BEGIN
  IF auth_role() <> 'distributeur' THEN
    RAISE EXCEPTION 'Réservé au distributeur' USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE livreurs
     SET actif = p_actif,
         -- Écarté, il ne doit plus apparaître en ligne sur la carte de personne.
         en_ligne = CASE WHEN p_actif THEN en_ligne ELSE false END
   WHERE id = p_livreur_id
     AND distributeur_id = auth_id_metier()
  RETURNING * INTO v_livreur;

  IF v_livreur.id IS NULL THEN
    RAISE EXCEPTION 'Ce livreur n''appartient pas à votre flotte'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN v_livreur;
END;
$fn$;

-- ── 6. Les marques et les boutiques du distributeur ─────────────────────────
--
-- « Gérer ses marques » se traduit dans le schéma par un triplet
-- (fabricant, boutique, distributeur) dans `attributions_reseau`. Déclarer une
-- marque sans boutique n'aurait aucun effet sur le routage : c'est le triplet,
-- et lui seul, qui dit où part une rupture.
--
-- RÈGLE DE REVENDICATION, qui n'est pas un détail technique mais la traduction
-- de la distribution ivoirienne :
--
--   * un distributeur AFFILIÉ à un fabricant (`fabricant_id` renseigné) ne
--     revendique que la marque de ce fabricant. Il ne peut pas prendre une
--     boutique au nom d'un concurrent de son propre mandant.
--   * un distributeur INDÉPENDANT revendique la marque qu'il veut, puisque
--     c'est précisément son métier d'en porter plusieurs.
--   * une boutique déjà revendiquée par un autre pour la même marque ne se
--     reprend pas. Premier arrivé, premier servi, et l'arbitrage d'un conflit
--     reste du ressort de l'administrateur.
--
-- LIMITE ASSUMÉE POUR LE PILOTE : rien ne vérifie qu'un distributeur porte
-- réellement la marque qu'il revendique. Sur dix boutiques à Cocody que tu
-- recenses toi-même, c'est sans conséquence. À l'ouverture, il faudra une
-- validation par le fabricant, qui est un écran de plus et une décision de
-- produit, pas une correction.
CREATE OR REPLACE FUNCTION revendiquer_point_de_vente(
  p_point_de_vente_id UUID,
  p_fabricant_id      UUID
)
RETURNS attributions_reseau
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_moi         UUID := auth_id_metier();
  v_mon_fab     UUID;
  v_detenteur   UUID;
  v_attribution attributions_reseau;
BEGIN
  IF auth_role() <> 'distributeur' THEN
    RAISE EXCEPTION 'Réservé au distributeur' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT fabricant_id INTO v_mon_fab FROM distributeurs WHERE id = v_moi;

  IF v_mon_fab IS NOT NULL AND v_mon_fab <> p_fabricant_id THEN
    RAISE EXCEPTION 'Vous êtes rattaché à une seule marque et ne pouvez pas revendiquer celle-ci'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM points_de_vente WHERE id = p_point_de_vente_id AND statut = 'actif'
  ) THEN
    RAISE EXCEPTION 'Boutique inconnue ou inactive' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT distributeur_id INTO v_detenteur
    FROM attributions_reseau
   WHERE point_de_vente_id = p_point_de_vente_id AND fabricant_id = p_fabricant_id;

  IF v_detenteur IS NOT NULL AND v_detenteur <> v_moi THEN
    RAISE EXCEPTION 'Cette boutique est déjà desservie par un autre distributeur pour cette marque'
      USING ERRCODE = 'unique_violation';
  END IF;

  INSERT INTO attributions_reseau (fabricant_id, point_de_vente_id, distributeur_id)
  VALUES (p_fabricant_id, p_point_de_vente_id, v_moi)
  ON CONFLICT (fabricant_id, point_de_vente_id)
  DO UPDATE SET distributeur_id = v_moi
  RETURNING * INTO v_attribution;

  RETURN v_attribution;
END;
$fn$;

CREATE OR REPLACE FUNCTION renoncer_point_de_vente(
  p_point_de_vente_id UUID,
  p_fabricant_id      UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_touchees INTEGER;
BEGIN
  IF auth_role() <> 'distributeur' THEN
    RAISE EXCEPTION 'Réservé au distributeur' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- La ligne d'attribution est conservée avec un distributeur nul plutôt que
  -- supprimée : elle dit toujours que ce fabricant couvre cette boutique, et
  -- les ruptures qui en naîtront partiront au cercle élargi au lieu de se
  -- perdre sans destinataire.
  UPDATE attributions_reseau
     SET distributeur_id = NULL
   WHERE point_de_vente_id = p_point_de_vente_id
     AND fabricant_id = p_fabricant_id
     AND distributeur_id = auth_id_metier();

  GET DIAGNOSTICS v_touchees = ROW_COUNT;
  RETURN v_touchees > 0;
END;
$fn$;

-- ── 7. Ce que les nouveaux écrans lisent ────────────────────────────────────

-- La flotte, avec l'état de chacun et son activité.
CREATE VIEW v_ma_flotte
WITH (security_invoker = on) AS
SELECT
  l.id AS livreur_id,
  u.nom,
  u.telephone,
  l.en_ligne,
  l.actif,
  l.position_maj_le,
  l.distributeur_id,
  (SELECT count(*) FROM livraisons lv
    WHERE lv.livreur_id = l.id AND lv.statut = 'en_cours')  AS courses_en_cours,
  (SELECT count(*) FROM livraisons lv
    WHERE lv.livreur_id = l.id AND lv.statut = 'terminee')  AS livraisons_terminees
FROM livreurs l
JOIN utilisateurs u ON u.id = l.utilisateur_id;

COMMENT ON VIEW v_ma_flotte IS
  'Les livreurs du distributeur connecté. Le filtrage vient de RLS, pas d''un paramètre.';

-- Les marques portées et leur couverture. Une marque sans boutique n'apparaît
-- pas : elle n'existe pas du point de vue du routage.
CREATE VIEW v_mes_marques
WITH (security_invoker = on) AS
SELECT
  f.id AS fabricant_id,
  f.nom AS fabricant_nom,
  ar.distributeur_id,
  count(*) AS boutiques,
  count(*) FILTER (WHERE pdv.statut = 'actif') AS boutiques_actives
FROM attributions_reseau ar
JOIN fabricants f ON f.id = ar.fabricant_id
JOIN points_de_vente pdv ON pdv.id = ar.point_de_vente_id
WHERE ar.distributeur_id IS NOT NULL
GROUP BY f.id, f.nom, ar.distributeur_id;

-- Les boutiques desservies, marque par marque.
CREATE VIEW v_mon_reseau
WITH (security_invoker = on) AS
SELECT
  ar.point_de_vente_id,
  pdv.nom AS point_de_vente_nom,
  pdv.commune,
  pdv.type_activite,
  pdv.telephone,
  ar.fabricant_id,
  f.nom AS fabricant_nom,
  ar.distributeur_id,
  (SELECT count(*) FROM ruptures r
    WHERE r.point_de_vente_id = ar.point_de_vente_id
      AND r.statut = 'signalee') AS ruptures_ouvertes
FROM attributions_reseau ar
JOIN points_de_vente pdv ON pdv.id = ar.point_de_vente_id
JOIN fabricants f ON f.id = ar.fabricant_id;

-- Ce que l'agent recenseur a inscrit, pour qu'il puisse vérifier son travail
-- et retrouver un numéro sans rappeler personne.
CREATE VIEW v_mes_recensements
WITH (security_invoker = on) AS
SELECT
  pdv.id AS point_de_vente_id,
  pdv.nom,
  pdv.type_activite,
  pdv.commune,
  pdv.adresse,
  pdv.gerant_nom,
  pdv.telephone,
  pdv.statut,
  pdv.created_at,
  pdv.agent_recenseur_id,
  ST_Y(pdv.position::GEOMETRY) AS latitude,
  ST_X(pdv.position::GEOMETRY) AS longitude
FROM points_de_vente pdv;

-- ── 8. Droits d'exécution ───────────────────────────────────────────────────

REVOKE EXECUTE ON FUNCTION creer_compte_metier, ecarter_livreur,
                           revendiquer_point_de_vente, renoncer_point_de_vente
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION creer_compte_metier, ecarter_livreur,
                          revendiquer_point_de_vente, renoncer_point_de_vente
  TO authenticated;

-- ── 9. Un livreur écarté ne reçoit plus de course ───────────────────────────
--
-- `affecter_livreur` vérifiait l'appartenance à la flotte mais pas l'activité,
-- ce qui n'existait pas encore. Sans ce contrôle, écarter un livreur serait
-- purement cosmétique : il disparaîtrait de la liste tout en restant affectable
-- par une requête directe.
-- Le type de retour ne change pas : la fonction rend `livraisons` depuis la
-- migration du cycle de livraison, et `CREATE OR REPLACE` refuse d'en changer.
-- Seule la condition d'appartenance à la flotte est resserrée.
CREATE OR REPLACE FUNCTION affecter_livreur(p_rupture_id UUID, p_livreur_id UUID)
RETURNS livraisons
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_distributeur_id UUID := auth_id_metier();
  v_rupture         ruptures;
  v_livraison       livraisons;
BEGIN
  IF auth_role() <> 'distributeur' THEN
    RAISE EXCEPTION 'Seul un distributeur peut affecter un livreur' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM livreurs
     WHERE id = p_livreur_id
       AND distributeur_id = v_distributeur_id
       AND actif
  ) THEN
    RAISE EXCEPTION 'Ce livreur ne fait pas partie de votre flotte, ou en a été écarté'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE ruptures r
     SET statut = 'prise_en_charge', livreur_id = p_livreur_id, date_prise_en_charge = now()
   WHERE r.id = p_rupture_id
     AND r.statut = 'signalee'
     AND distributeur_voit_rupture(r.id, v_distributeur_id)
  RETURNING r.* INTO v_rupture;

  IF v_rupture.id IS NULL THEN
    RAISE EXCEPTION 'Course indisponible : déjà prise, inexistante, ou hors de votre périmètre'
      USING ERRCODE = 'lock_not_available';
  END IF;

  INSERT INTO livraisons (rupture_id, livreur_id, point_de_vente_id, statut)
  VALUES (v_rupture.id, p_livreur_id, v_rupture.point_de_vente_id, 'en_cours')
  RETURNING * INTO v_livraison;

  RETURN v_livraison;
END;
$fn$;

-- ── 10. Diffusion temps réel des livraisons ─────────────────────────────────
--
-- `ruptures` et `positions_livreurs` étaient publiées, mais pas `livraisons`.
-- Or c'est la table qui change quand une course est affectée à un livreur : sans
-- elle, l'onglet « Mes courses » du livreur ne se réveille jamais tout seul.
-- `stocks` rejoint la publication pour une raison précise : c'est la dernière
-- étape du parcours qui prouve le produit. Le livreur livre, la base
-- réapprovisionne, et le boutiquier doit voir son stock remonter sans rien
-- toucher. Sans diffusion, il ne le voit qu'au prochain rafraîchissement manuel,
-- et le seul instant où Yalla se montre lui échappe.
DO $bloc$
DECLARE
  v_table TEXT;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['livraisons', 'stocks'] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = v_table
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE %I', v_table);
    END IF;
  END LOOP;
END;
$bloc$;

-- Sans REPLICA IDENTITY FULL, un évènement de mise à jour ne porte que la clé
-- primaire, et les politiques RLS du canal temps réel ne peuvent pas décider si
-- l'abonné a le droit de le recevoir : il ne reçoit alors rien.
ALTER TABLE livraisons REPLICA IDENTITY FULL;
ALTER TABLE stocks     REPLICA IDENTITY FULL;
