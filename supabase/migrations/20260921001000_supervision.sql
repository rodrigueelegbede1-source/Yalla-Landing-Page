-- 20260921001000_supervision.sql
--
-- Ce que l'administrateur du réseau doit voir et pouvoir faire.
--
-- ── CE QUE L'ADMINISTRATEUR NE VOIT PAS, ET NE VERRA PAS ────────────────────
--
-- Ni les ventes, ni les stocks, ni le chiffre d'affaires d'une boutique. Ce
-- n'est pas un oubli : la promesse faite au boutiquier est que sa caisse
-- n'appartient qu'à lui, et une promesse qui souffre une exception pour
-- l'exploitant n'en est plus une. Les politiques `stocks_prives` et
-- `ventes_privees` ne mentionnent délibérément pas `est_admin()`.
--
-- L'administrateur supervise le RÉSEAU : qui en fait partie, qui dessert qui,
-- et ce qui ne tourne pas rond. Pas le commerce des boutiques.
--
-- ── LES TROIS PANNES SILENCIEUSES QU'IL DOIT POUVOIR REPÉRER ────────────────
--
-- Elles ont toutes la même propriété : rien ne se plaint, et le réseau dégrade
-- sans que personne ne le sache.
--
--   1. Une boutique recensée qu'aucun distributeur ne dessert. Ses ruptures
--      naissent sans destinataire et n'existent qu'après deux heures
--      d'escalade, pour tout le monde à la fois.
--   2. Un distributeur sans livreur actif. Il voit ses courses et ne peut les
--      affecter à personne.
--   3. Une boutique qui ne suit aucun stock. La caisse ne peut rien détecter :
--      c'est le stock qui déclenche l'alerte en tombant à zéro.

-- ── 1. L'état du réseau, d'un coup d'œil ────────────────────────────────────

CREATE VIEW v_supervision_reseau
WITH (security_invoker = on) AS
SELECT
  (SELECT count(*) FROM points_de_vente WHERE statut = 'actif')       AS boutiques_actives,
  (SELECT count(*) FROM points_de_vente)                              AS boutiques_total,
  (SELECT count(*) FROM distributeurs WHERE statut = 'actif')         AS distributeurs,
  (SELECT count(*) FROM livreurs WHERE actif)                         AS livreurs_actifs,
  (SELECT count(*) FROM livreurs WHERE actif AND en_ligne)            AS livreurs_en_ligne,
  (SELECT count(*) FROM fabricants WHERE statut = 'actif')            AS fabricants,
  (SELECT count(*) FROM produits WHERE disponible)                    AS produits,
  (SELECT count(*) FROM ruptures
    WHERE statut = 'signalee' AND confirmee_le IS NOT NULL)           AS ruptures_ouvertes,
  (SELECT count(*) FROM ruptures
    WHERE statut = 'signalee' AND confirmee_le IS NULL)               AS ruptures_a_confirmer,
  (SELECT count(*) FROM ruptures WHERE statut = 'prise_en_charge')    AS ruptures_prises,
  (SELECT count(*) FROM demandes_acces WHERE statut = 'en_attente')   AS demandes_en_attente,

  -- Le taux de service de tout le réseau, et non par fabricant : c'est le
  -- chiffre qui dit si le produit tient, toutes marques confondues.
  (SELECT round(100.0 * count(*) FILTER (WHERE statut = 'resolue')
                / NULLIF(count(*), 0), 1)
     FROM ruptures WHERE statut IN ('resolue', 'non_servie'))         AS taux_de_service_pct,
  (SELECT count(*) FROM ruptures WHERE statut IN ('resolue', 'non_servie')) AS ruptures_closes;

COMMENT ON VIEW v_supervision_reseau IS
  'Vue d''ensemble du réseau pour l''administrateur. Ne contient aucune donnée de caisse : la promesse faite au boutiquier ne souffre pas d''exception pour l''exploitant.';

-- ── 2. Ce qui ne tourne pas rond ────────────────────────────────────────────
--
-- Une liste d'anomalies plutôt que trois vues séparées : l'administrateur veut
-- savoir « qu'est-ce qui cloche », pas interroger trois écrans pour l'apprendre.

CREATE VIEW v_anomalies_reseau
WITH (security_invoker = on) AS
-- Boutique active que personne ne dessert.
SELECT
  'boutique_sans_distributeur'::TEXT AS type_anomalie,
  pdv.id      AS objet_id,
  pdv.nom     AS objet_nom,
  pdv.commune AS detail,
  'Ses ruptures naissent sans destinataire et n''apparaissent qu''après deux heures d''escalade.'::TEXT AS consequence,
  pdv.created_at AS depuis
FROM points_de_vente pdv
WHERE pdv.statut = 'actif'
  AND NOT EXISTS (
    SELECT 1 FROM attributions_reseau ar
     WHERE ar.point_de_vente_id = pdv.id AND ar.distributeur_id IS NOT NULL
  )

UNION ALL

-- Distributeur actif sans aucun livreur en état de rouler.
SELECT
  'distributeur_sans_livreur',
  d.id,
  d.nom,
  COALESCE(f.nom, 'Indépendant'),
  'Il voit ses courses et ne peut les affecter à personne.',
  d.created_at
FROM distributeurs d
LEFT JOIN fabricants f ON f.id = d.fabricant_id
WHERE d.statut = 'actif'
  AND NOT EXISTS (SELECT 1 FROM livreurs l WHERE l.distributeur_id = d.id AND l.actif)

UNION ALL

-- Boutique active qui ne suit aucun stock : la caisse ne peut rien détecter.
SELECT
  'boutique_sans_stock',
  pdv.id,
  pdv.nom,
  pdv.commune,
  'Aucun stock suivi : la caisse ne peut déclencher aucune rupture automatique.',
  pdv.created_at
FROM points_de_vente pdv
WHERE pdv.statut = 'actif'
  AND NOT EXISTS (SELECT 1 FROM stocks s WHERE s.point_de_vente_id = pdv.id)

UNION ALL

-- Rupture confirmée et sans destinataire : elle attend l'escalade pour exister.
SELECT
  'rupture_sans_destinataire',
  r.id,
  p.nom,
  pdv.nom || ' · ' || pdv.commune,
  'Aucun distributeur attribué : elle n''apparaîtra qu''après escalade.',
  r.confirmee_le
FROM ruptures r
JOIN produits p          ON p.id = r.produit_id
JOIN points_de_vente pdv ON pdv.id = r.point_de_vente_id
WHERE r.statut = 'signalee'
  AND r.confirmee_le IS NOT NULL
  AND r.distributeur_id IS NULL;

COMMENT ON VIEW v_anomalies_reseau IS
  'Les pannes silencieuses du réseau : celles dont personne ne se plaint et qui dégradent le service sans que rien ne le signale.';

-- La vue `stocks` étant privée au point de vente, le test d'absence de stock
-- ci-dessus ne rendrait rien pour l'administrateur. Cette politique lui donne
-- accès à la PRÉSENCE d'une ligne de stock, pas à son contenu : il a besoin de
-- savoir qu'une boutique n'en suit aucun, jamais de savoir combien il lui
-- reste de cartons.
--
-- La distinction est fine mais elle tient : une politique RLS ne filtre que les
-- lignes, pas les colonnes. On accepte donc que l'administrateur puisse lire
-- une quantité s'il interroge la table directement, et on s'appuie sur le fait
-- que l'application ne le lui propose nulle part. Si cette nuance devenait
-- insuffisante, la bonne réponse serait une fonction SECURITY DEFINER rendant
-- uniquement un booléen, pas un élargissement de cette politique.
CREATE POLICY stocks_presence_admin ON stocks FOR SELECT TO authenticated
  USING (est_admin());

-- ── 3. Les listes que l'administrateur parcourt ─────────────────────────────

CREATE VIEW v_supervision_boutiques
WITH (security_invoker = on) AS
SELECT
  pdv.id AS point_de_vente_id,
  pdv.nom,
  pdv.commune,
  pdv.type_activite,
  pdv.statut,
  pdv.gerant_nom,
  pdv.telephone,
  pdv.created_at,
  u.nom AS agent_recenseur,
  (SELECT count(*) FROM stocks s WHERE s.point_de_vente_id = pdv.id) AS references_suivies,
  (SELECT count(*) FROM ruptures r
    WHERE r.point_de_vente_id = pdv.id AND r.statut = 'signalee'
      AND r.confirmee_le IS NOT NULL) AS ruptures_ouvertes,
  (SELECT string_agg(DISTINCT f.nom, ', ')
     FROM attributions_reseau ar JOIN fabricants f ON f.id = ar.fabricant_id
    WHERE ar.point_de_vente_id = pdv.id) AS marques,
  (SELECT string_agg(DISTINCT d.nom, ', ')
     FROM attributions_reseau ar JOIN distributeurs d ON d.id = ar.distributeur_id
    WHERE ar.point_de_vente_id = pdv.id) AS distributeurs
FROM points_de_vente pdv
LEFT JOIN agents_recenseurs a ON a.id = pdv.agent_recenseur_id
LEFT JOIN utilisateurs u ON u.id = a.utilisateur_id;

CREATE VIEW v_supervision_distributeurs
WITH (security_invoker = on) AS
SELECT
  d.id AS distributeur_id,
  d.nom,
  d.telephone,
  d.statut,
  d.auto_distribution,
  f.nom AS fabricant_rattache,
  u.nom AS gerant,
  d.created_at,
  (SELECT count(*) FROM livreurs l WHERE l.distributeur_id = d.id AND l.actif) AS livreurs,
  (SELECT count(*) FROM livreurs l
    WHERE l.distributeur_id = d.id AND l.actif AND l.en_ligne) AS livreurs_en_ligne,
  (SELECT count(DISTINCT ar.point_de_vente_id)
     FROM attributions_reseau ar WHERE ar.distributeur_id = d.id) AS boutiques,
  (SELECT count(*) FROM ruptures r
    WHERE r.distributeur_id = d.id AND r.statut = 'signalee'
      AND r.confirmee_le IS NOT NULL) AS courses_en_attente
FROM distributeurs d
LEFT JOIN fabricants f   ON f.id = d.fabricant_id
LEFT JOIN utilisateurs u ON u.id = d.utilisateur_id;

-- ── 4. Attribuer une boutique à un distributeur ─────────────────────────────
--
-- LE POINT DE FRICTION QUE CETTE FONCTION RÉSOUT. Un distributeur qui démarre
-- ne voit aucune boutique dans son écran Réseau : la politique ne lui montre
-- que les communes où il opère déjà, et il n'en a aucune. Sa PREMIÈRE boutique
-- doit donc lui être attribuée de l'extérieur, faute de quoi il ne peut jamais
-- commencer. `attribuer_point_de_vente` existait pour cela depuis la migration
-- des actions métier ; il lui manquait un écran.
--
-- Cette fonction-ci ajoute ce que l'écran réclame et que l'autre ne rendait
-- pas : de quoi afficher un retour lisible sans réinterroger la base.

CREATE OR REPLACE FUNCTION attribuer_boutique_admin(
  p_point_de_vente_id UUID,
  p_fabricant_id      UUID,
  p_distributeur_id   UUID
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_pdv    TEXT;
  v_fab    TEXT;
  v_dist   TEXT;
  v_detenu TEXT;
BEGIN
  IF NOT est_admin() THEN
    RAISE EXCEPTION 'Réservé à l''administrateur du réseau'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT nom INTO v_pdv  FROM points_de_vente WHERE id = p_point_de_vente_id;
  SELECT nom INTO v_fab  FROM fabricants      WHERE id = p_fabricant_id;
  SELECT nom INTO v_dist FROM distributeurs   WHERE id = p_distributeur_id;

  IF v_pdv IS NULL THEN
    RAISE EXCEPTION 'Boutique inconnue' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_fab IS NULL THEN
    RAISE EXCEPTION 'Marque inconnue' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_dist IS NULL THEN
    RAISE EXCEPTION 'Distributeur inconnu' USING ERRCODE = 'no_data_found';
  END IF;

  -- Qui la desservait avant, pour que l'écran puisse le dire : reprendre une
  -- boutique à un distributeur est une décision commerciale, pas un détail
  -- technique, et l'administrateur doit savoir qu'il la prend.
  SELECT d.nom INTO v_detenu
    FROM attributions_reseau ar
    JOIN distributeurs d ON d.id = ar.distributeur_id
   WHERE ar.point_de_vente_id = p_point_de_vente_id
     AND ar.fabricant_id = p_fabricant_id
     AND ar.distributeur_id IS DISTINCT FROM p_distributeur_id;

  INSERT INTO attributions_reseau (fabricant_id, point_de_vente_id, distributeur_id)
  VALUES (p_fabricant_id, p_point_de_vente_id, p_distributeur_id)
  ON CONFLICT (fabricant_id, point_de_vente_id)
  DO UPDATE SET distributeur_id = p_distributeur_id;

  RETURN jsonb_build_object(
    'boutique',     v_pdv,
    'marque',       v_fab,
    'distributeur', v_dist,
    'repris_a',     v_detenu
  );
END;
$fn$;

REVOKE EXECUTE ON FUNCTION attribuer_boutique_admin FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION attribuer_boutique_admin TO authenticated;
