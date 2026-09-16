-- 20260916007000_cycle_de_livraison.sql
--
-- Ferme le cycle d'une course, de la prise à la livraison.
--
-- DEUX TROUS COMBLÉS ICI, trouvés en construisant l'écran du livreur :
--
--  1. **Rien ne créait de ligne dans `livraisons`.** `prendre_rupture()` passait
--     la rupture en « prise en charge », mais `terminer_livraison()` attendait
--     un identifiant de livraison qui n'existait nulle part. Le cycle ne pouvait
--     donc pas se terminer : une course prise restait ouverte indéfiniment, et
--     le trigger `trg_livraisons_resout_rupture`, qui clôt la rupture quand la
--     livraison se termine, n'avait jamais l'occasion de se déclencher.
--
--  2. **Un livreur ne pouvait pas abandonner une course.** Une panne de moto,
--     une boutique fermée, une erreur de clic, et la rupture restait bloquée en
--     « prise en charge » pour toujours : plus personne ne pouvait la prendre,
--     et l'escalade ne la voyait plus puisqu'elle ne cherche que les ruptures
--     encore au statut `signalee`. Une seule fausse manœuvre suffisait à faire
--     disparaître une rupture du circuit.
--
-- Prendre une course et démarrer une livraison sont désormais le même geste, en
-- une seule transaction. C'est plus juste métier, et cela supprime l'état
-- bâtard « rupture prise mais sans livraison ».

-- Le type de retour change : il faut supprimer avant de recréer.
DROP FUNCTION IF EXISTS prendre_rupture(UUID);
DROP FUNCTION IF EXISTS affecter_livreur(UUID, UUID);

-- ── 1. Prendre une course ──────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION prendre_rupture(p_rupture_id UUID)
RETURNS livraisons
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_livreur_id      UUID := auth_id_metier();
  v_distributeur_id UUID;
  v_rupture         ruptures;
  v_livraison       livraisons;
BEGIN
  IF auth_role() <> 'livreur' THEN
    RAISE EXCEPTION 'Seul un livreur peut prendre une course' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT distributeur_id INTO v_distributeur_id FROM livreurs WHERE id = v_livreur_id;
  IF v_distributeur_id IS NULL THEN
    RAISE EXCEPTION 'Livreur introuvable ou sans distributeur' USING ERRCODE = 'no_data_found';
  END IF;

  -- Le verrou : conditionné sur `signalee`, donc le premier arrivé gagne et les
  -- suivants ne touchent aucune ligne.
  UPDATE ruptures r
     SET statut = 'prise_en_charge', livreur_id = v_livreur_id, date_prise_en_charge = now()
   WHERE r.id = p_rupture_id
     AND r.statut = 'signalee'
     AND distributeur_voit_rupture(r.id, v_distributeur_id)
  RETURNING r.* INTO v_rupture;

  IF v_rupture.id IS NULL THEN
    SELECT * INTO v_rupture FROM ruptures WHERE id = p_rupture_id;
    IF v_rupture.id IS NULL THEN
      RAISE EXCEPTION 'Course introuvable' USING ERRCODE = 'no_data_found';
    ELSIF v_rupture.statut <> 'signalee' THEN
      RAISE EXCEPTION 'Cette course vient d''être prise par un autre livreur'
        USING ERRCODE = 'lock_not_available';
    ELSE
      RAISE EXCEPTION 'Cette course ne relève pas de votre distributeur'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- Même transaction : une course prise a forcément sa livraison.
  INSERT INTO livraisons (rupture_id, livreur_id, point_de_vente_id, statut)
  VALUES (v_rupture.id, v_livreur_id, v_rupture.point_de_vente_id, 'en_cours')
  RETURNING * INTO v_livraison;

  RETURN v_livraison;
END;
$fn$;

-- ── 2. Affecter un livreur, côté distributeur ──────────────────────────────

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

  IF NOT EXISTS (SELECT 1 FROM livreurs WHERE id = p_livreur_id AND distributeur_id = v_distributeur_id) THEN
    RAISE EXCEPTION 'Ce livreur ne fait pas partie de votre flotte' USING ERRCODE = 'insufficient_privilege';
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

-- ── 3. Abandonner une course ───────────────────────────────────────────────
--
-- La rupture **doit** repasser à `signalee`, sinon elle sort du circuit pour de
-- bon : plus personne ne peut la prendre, et l'escalade ne la voit plus.
--
-- `escaladee_le` est remis à NULL et `date_signalement` rafraîchie, pour que le
-- compte à rebours reparte de zéro. Sans cela, une course abandonnée après deux
-- heures s'ouvrirait immédiatement à tous les distributeurs de la commune, ce
-- qui punirait le distributeur attribué pour la panne de moto de son livreur.

CREATE OR REPLACE FUNCTION annuler_livraison(p_livraison_id UUID)
RETURNS livraisons
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_livreur_id UUID := auth_id_metier();
  v_livraison  livraisons;
BEGIN
  IF auth_role() <> 'livreur' THEN
    RAISE EXCEPTION 'Seul le livreur peut abandonner sa course' USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE livraisons
     SET statut = 'annulee', date_fin = now()
   WHERE id = p_livraison_id
     AND livreur_id = v_livreur_id
     AND statut = 'en_cours'
  RETURNING * INTO v_livraison;

  IF v_livraison.id IS NULL THEN
    RAISE EXCEPTION 'Course introuvable, déjà close, ou qui ne vous appartient pas'
      USING ERRCODE = 'no_data_found';
  END IF;

  -- On remet la rupture en circulation.
  IF v_livraison.rupture_id IS NOT NULL THEN
    UPDATE ruptures
       SET statut = 'signalee',
           livreur_id = NULL,
           date_prise_en_charge = NULL,
           escaladee_le = NULL,
           date_signalement = now()
     WHERE id = v_livraison.rupture_id
       AND statut = 'prise_en_charge';
  END IF;

  RETURN v_livraison;
END;
$fn$;

-- ── 4. Droits ──────────────────────────────────────────────────────────────

REVOKE EXECUTE ON FUNCTION prendre_rupture, affecter_livreur, annuler_livraison
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION prendre_rupture, affecter_livreur, annuler_livraison
  TO authenticated;

-- ── 5. Ce que l'écran de livraison consomme ────────────────────────────────

CREATE VIEW v_mes_courses
WITH (security_invoker = on) AS
SELECT
  l.id                AS livraison_id,
  l.rupture_id,
  l.statut            AS statut_livraison,
  l.date_debut,
  l.montant,
  pdv.id              AS point_de_vente_id,
  pdv.nom             AS point_de_vente_nom,
  pdv.adresse,
  pdv.commune,
  pdv.telephone       AS point_de_vente_telephone,
  pdv.gerant_nom,
  ST_Y(pdv.position::geometry) AS latitude,
  ST_X(pdv.position::geometry) AS longitude,
  p.nom               AS produit_nom,
  p.reference         AS produit_reference,
  f.nom               AS fabricant_nom,
  r.quantite_demandee,
  r.statut            AS statut_rupture
FROM livraisons l
JOIN points_de_vente pdv ON pdv.id = l.point_de_vente_id
LEFT JOIN ruptures r     ON r.id = l.rupture_id
LEFT JOIN produits p     ON p.id = r.produit_id
LEFT JOIN fabricants f   ON f.id = p.fabricant_id;

COMMENT ON VIEW v_mes_courses IS
  'Écran de livraison. Filtré par RLS : un livreur n''y voit que ses propres courses.';
