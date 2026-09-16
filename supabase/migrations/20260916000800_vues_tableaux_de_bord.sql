-- 008_vues_tableaux_de_bord.sql
-- Vues consommées directement par les endpoints des maquettes Administrateur et Fabricant
-- (CA temps réel, ruptures en cours) plutôt que de recalculer ces agrégats côté application.

CREATE VIEW v_chiffre_affaires_par_fabricant AS
SELECT
  f.id AS fabricant_id,
  f.nom AS fabricant_nom,
  COALESCE(SUM(l.montant) FILTER (WHERE l.statut = 'terminee'), 0) AS chiffre_affaires
FROM fabricants f
LEFT JOIN livreurs lv ON lv.fabricant_id = f.id
LEFT JOIN livraisons l ON l.livreur_id = lv.id
GROUP BY f.id, f.nom;

CREATE VIEW v_chiffre_affaires_par_livreur AS
SELECT
  lv.id AS livreur_id,
  u.nom AS livreur_nom,
  lv.fabricant_id,
  COALESCE(SUM(l.montant) FILTER (WHERE l.statut = 'terminee'), 0) AS chiffre_affaires,
  COUNT(l.id) FILTER (WHERE l.statut = 'terminee') AS nombre_livraisons
FROM livreurs lv
JOIN utilisateurs u ON u.id = lv.utilisateur_id
LEFT JOIN livraisons l ON l.livreur_id = lv.id
GROUP BY lv.id, u.nom, lv.fabricant_id;

-- Ruptures actuellement ouvertes ('signalee' ou 'prise_en_charge'), avec le fabricant
-- concerné déduit du produit — sert à la fois la vue Administrateur (tout le réseau)
-- et la vue Fabricant (filtrer ensuite sur fabricant_id).
CREATE VIEW v_ruptures_ouvertes AS
SELECT
  r.id AS rupture_id,
  r.point_de_vente_id,
  pdv.nom AS point_de_vente_nom,
  pdv.commune,
  pdv.position,
  r.produit_id,
  p.nom AS produit_nom,
  p.fabricant_id,
  r.statut,
  r.signalement_automatique,
  r.date_signalement
FROM ruptures r
JOIN points_de_vente pdv ON pdv.id = r.point_de_vente_id
JOIN produits p ON p.id = r.produit_id
WHERE r.statut IN ('signalee', 'prise_en_charge');

-- Exemple de requête (pas une vue, car elle dépend d'un point de référence) pour le
-- cas d'usage central de l'interface Livreur : "les ruptures de mon catalogue les
-- plus proches de ma position actuelle", en utilisant l'index spatial GIST posé sur
-- ruptures via points_de_vente.position :
--
-- SELECT ro.*, ST_Distance(ro.position, l.position) AS distance_metres
-- FROM v_ruptures_ouvertes ro
-- JOIN livreurs l ON l.id = :livreur_id
-- WHERE ro.fabricant_id = l.fabricant_id
-- ORDER BY ro.position <-> l.position
-- LIMIT 20;
