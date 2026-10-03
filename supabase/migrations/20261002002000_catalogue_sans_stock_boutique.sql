-- Le parcours boutique est désormais un catalogue de signalement, sans
-- inventaire tenu dans l'application. Les données de stock historiques restent
-- présentes, mais elles ne définissent plus l'état du réseau.

DROP POLICY IF EXISTS stocks_presence_admin ON stocks;

CREATE OR REPLACE VIEW v_anomalies_reseau
WITH (security_invoker = on) AS
-- Boutique active que personne ne dessert.
SELECT
  'boutique_sans_distributeur'::TEXT AS type_anomalie,
  pdv.id      AS objet_id,
  pdv.nom     AS objet_nom,
  pdv.commune AS detail,
  'Ses ruptures n''ont pas de destinataire attribué.'::TEXT AS consequence,
  pdv.created_at AS depuis
FROM points_de_vente pdv
WHERE pdv.statut = 'actif'
  AND NOT EXISTS (
    SELECT 1 FROM attributions_reseau ar
     WHERE ar.point_de_vente_id = pdv.id AND ar.distributeur_id IS NOT NULL
  )

UNION ALL

-- Distributeur actif sans aucun livreur.
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

-- Rupture confirmée et sans destinataire.
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
  'Les anomalies de distribution : boutique sans distributeur, distributeur sans livreur et rupture sans destinataire.';
GRANT SELECT ON v_anomalies_reseau TO authenticated;

DROP VIEW v_supervision_communes;
CREATE VIEW v_supervision_communes
WITH (security_invoker = on) AS
SELECT
  pdv.commune,
  count(*) FILTER (WHERE pdv.statut = 'actif')  AS points,
  count(*) FILTER (WHERE pdv.statut <> 'actif') AS points_inactifs,
  count(*) FILTER (WHERE pdv.statut = 'actif' AND NOT EXISTS (
    SELECT 1 FROM attributions_reseau ar
     WHERE ar.point_de_vente_id = pdv.id AND ar.distributeur_id IS NOT NULL
  )) AS points_sans_distributeur,
  (SELECT count(*) FROM ruptures r
     JOIN points_de_vente p2 ON p2.id = r.point_de_vente_id
    WHERE p2.commune = pdv.commune
      AND r.statut = 'signalee' AND r.confirmee_le IS NOT NULL) AS ruptures
FROM points_de_vente pdv
GROUP BY pdv.commune;

DROP VIEW v_supervision_boutiques;
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

COMMENT ON VIEW v_supervision_boutiques IS
  'Liste réseau des boutiques sans donnée de stock ou de vente.';

GRANT SELECT ON v_anomalies_reseau, v_supervision_communes, v_supervision_boutiques TO authenticated;