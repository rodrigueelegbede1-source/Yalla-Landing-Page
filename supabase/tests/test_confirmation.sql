-- test_confirmation.sql
--
-- La rupture détectée par la caisse attend l'accord du boutiquier.
--
--   psql -v ON_ERROR_STOP=1 -d yalla -f supabase/tests/test_confirmation.sql
--
-- POURQUOI CETTE RÈGLE MÉRITE SA PROPRE SUITE. Elle inverse le mécanisme
-- central du produit : jusqu'au 18/09/2026, une rupture partait seule et le
-- boutiquier n'avait rien à faire. Désormais elle n'existe pour personne tant
-- qu'il n'a pas répondu, et chaque chemin par lequel un distributeur pourrait
-- la voir quand même doit rester fermé. C'est exactement le genre de règle
-- qu'une modification ultérieure rouvre sans s'en apercevoir.
--
-- Tout se déroule dans une transaction close par ROLLBACK.

BEGIN;

DO $test$
DECLARE
  v_pdv       UUID;
  v_produit   UUID;
  v_dist      UUID;
  v_rupture   UUID;
  v_autre     UUID;
  v_nb        INTEGER;
  v_confirmee TIMESTAMPTZ;
  v_qte       INTEGER;
  v_secondes  INTEGER;
BEGIN
  SELECT id INTO v_dist FROM distributeurs WHERE nom = 'Distrib Cocody';
  SELECT r.point_de_vente_id, r.produit_id INTO v_pdv, v_produit
    FROM ruptures r WHERE r.signalement_automatique LIMIT 1;

  ASSERT v_dist IS NOT NULL,    'Seed absent : lancez supabase db reset';
  ASSERT v_pdv IS NOT NULL,     'Seed absent : aucune rupture automatique';

  -- On repart d'une base propre de ruptures pour ce point de vente, afin que
  -- les comptages ne dépendent pas de ce que le seed a laissé.
  DELETE FROM livraisons WHERE rupture_id IN (SELECT id FROM ruptures WHERE point_de_vente_id = v_pdv);
  DELETE FROM ruptures WHERE point_de_vente_id = v_pdv;

  -- ── 1. Une rupture de caisse naît non confirmée ──────────────────────────
  INSERT INTO ruptures (point_de_vente_id, produit_id, statut,
                        signalement_automatique, quantite_demandee)
  VALUES (v_pdv, v_produit, 'signalee', true, 4)
  RETURNING id INTO v_rupture;

  SELECT confirmee_le INTO v_confirmee FROM ruptures WHERE id = v_rupture;
  ASSERT v_confirmee IS NULL, 'Une rupture automatique ne doit pas naître confirmée';
  RAISE NOTICE '  ok  caisse : la rupture détectée attend l''accord du boutiquier';

  -- Elle est pourtant bien routée : le destinataire est résolu à l'insertion,
  -- seule sa VISIBILITÉ est suspendue. Sans cela, confirmer une rupture
  -- reviendrait à la router après coup, et le routage dépendrait de l'instant
  -- de la confirmation plutôt que de l'attribution du réseau.
  ASSERT (SELECT distributeur_id FROM ruptures WHERE id = v_rupture) IS NOT NULL,
    'Une rupture non confirmée doit quand même avoir son destinataire résolu';
  RAISE NOTICE '  ok  routage : le destinataire est résolu avant la confirmation';

  -- ── 2. Personne ne la voit, par aucun chemin ─────────────────────────────
  SELECT count(*) INTO v_nb FROM v_acces_rupture_distributeur WHERE rupture_id = v_rupture;
  ASSERT v_nb = 0, format('Vue d''accès : 0 attendu, %s trouvé(s)', v_nb);

  ASSERT NOT distributeur_voit_rupture(v_rupture, v_dist),
    'La fonction d''aide RLS laisse passer une rupture non confirmée';
  RAISE NOTICE '  ok  invisibilité : ni la vue d''accès ni la fonction RLS ne la montrent';

  -- ── 3. Elle ne s'escalade pas et ne périme pas ───────────────────────────
  -- Une rupture en attente d'accord ne doit pas voir son compte à rebours
  -- tourner : le distributeur n'a jamais été sollicité, il ne peut pas être
  -- tenu pour responsable du délai.
  UPDATE ruptures SET date_signalement = now() - INTERVAL '5 hours' WHERE id = v_rupture;

  SELECT count(*) INTO v_nb
    FROM escalader_ruptures_en_attente() WHERE action IN ('escaladee', 'perimee');
  ASSERT v_nb = 0,
    format('Une rupture non confirmée ne doit ni s''escalader ni périmer, %s action(s)', v_nb);
  RAISE NOTICE '  ok  délais : le compte à rebours ne tourne pas avant l''accord';

  -- ── 4. Elle finit par être abandonnée, sans compter comme un échec ───────
  UPDATE ruptures SET date_signalement = now() - INTERVAL '30 hours' WHERE id = v_rupture;

  SELECT count(*) INTO v_nb
    FROM escalader_ruptures_en_attente() WHERE action = 'confirmation_abandonnee';
  ASSERT v_nb = 1, format('1 abandon attendu, %s obtenu(s)', v_nb);

  -- Supprimée et non close en « non_servie » : la compter comme un échec
  -- ferait chuter le taux de service vendu au fabricant pour une rupture que
  -- personne ne lui a jamais soumise.
  ASSERT NOT EXISTS (SELECT 1 FROM ruptures WHERE id = v_rupture),
    'Une demande abandonnée doit disparaître, pas devenir non_servie';
  RAISE NOTICE '  ok  abandon : une demande sans réponse ne pénalise pas le taux de service';

  -- ── 5. Le boutiquier confirme, et peut corriger la quantité ─────────────
  INSERT INTO ruptures (point_de_vente_id, produit_id, statut,
                        signalement_automatique, quantite_demandee)
  VALUES (v_pdv, v_produit, 'signalee', true, 4)
  RETURNING id INTO v_rupture;

  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'point_de_vente', 'id_metier', v_pdv)::TEXT, true);

  SELECT count(*) INTO v_nb FROM v_ruptures_a_confirmer WHERE rupture_id = v_rupture;
  ASSERT v_nb = 1, 'La rupture devrait figurer dans les demandes à confirmer';

  PERFORM confirmer_rupture(v_rupture, 9);

  SELECT confirmee_le, quantite_demandee INTO v_confirmee, v_qte
    FROM ruptures WHERE id = v_rupture;
  ASSERT v_confirmee IS NOT NULL, 'La confirmation n''a pas été enregistrée';
  ASSERT v_qte = 9,
    format('La quantité corrigée devrait être 9, trouvée %s', v_qte);
  RAISE NOTICE '  ok  confirmation : la quantité est révisable au moment d''accepter';

  SELECT count(*) INTO v_nb FROM v_ruptures_a_confirmer WHERE rupture_id = v_rupture;
  ASSERT v_nb = 0, 'Une rupture confirmée ne doit plus figurer dans les demandes';

  -- ── 6. Le compte à rebours part de la confirmation ──────────────────────
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'distributeur', 'id_metier', v_dist)::TEXT, true);

  SELECT secondes_avant_escalade INTO v_secondes
    FROM v_carnet_distributeur WHERE rupture_id = v_rupture;
  ASSERT v_secondes IS NOT NULL, 'La rupture confirmée devrait être au carnet';
  ASSERT v_secondes > 7000,
    format('Le compte à rebours devrait repartir de deux heures, trouvé %s s', v_secondes);
  RAISE NOTICE '  ok  carnet : le délai des deux heures démarre à la confirmation';

  -- ── 7. Un autre rôle ne peut pas confirmer à sa place ───────────────────
  BEGIN
    PERFORM confirmer_rupture(v_rupture);
    RAISE EXCEPTION 'Un distributeur a pu confirmer une rupture';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok  périmètre : seul le point de vente confirme ses ruptures';
  END;

  -- ── 8. Un autre point de vente non plus ─────────────────────────────────
  SELECT id INTO v_autre FROM points_de_vente WHERE id <> v_pdv LIMIT 1;
  IF v_autre IS NOT NULL THEN
    INSERT INTO ruptures (point_de_vente_id, produit_id, statut,
                          signalement_automatique, quantite_demandee)
    VALUES (v_pdv, v_produit, 'signalee', true, 2)
    RETURNING id INTO v_rupture;

    PERFORM set_config('request.jwt.claims',
      json_build_object('user_role', 'point_de_vente', 'id_metier', v_autre)::TEXT, true);
    BEGIN
      PERFORM confirmer_rupture(v_rupture);
      RAISE EXCEPTION 'Une boutique a pu confirmer la rupture d''une autre';
    EXCEPTION WHEN no_data_found THEN
      RAISE NOTICE '  ok  périmètre : une boutique ne confirme que ses propres ruptures';
    END;
  END IF;

  -- ── 9. Le rejet supprime sans pénaliser ─────────────────────────────────
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'point_de_vente', 'id_metier', v_pdv)::TEXT, true);

  ASSERT rejeter_rupture(v_rupture), 'Le rejet aurait dû aboutir';
  ASSERT NOT EXISTS (SELECT 1 FROM ruptures WHERE id = v_rupture),
    'Une rupture rejetée doit disparaître';
  RAISE NOTICE '  ok  rejet : la rupture refusée disparaît sans compter comme non servie';

  -- ── 10. Le signalement manuel est confirmé d'office ─────────────────────
  -- Il vient du boutiquier : lui redemander son accord n'aurait aucun sens.
  SELECT id INTO v_produit FROM produits WHERE disponible LIMIT 1;
  DELETE FROM ruptures WHERE point_de_vente_id = v_pdv;

  SELECT id, confirmee_le INTO v_rupture, v_confirmee
    FROM signaler_rupture(v_produit, 6);

  ASSERT v_confirmee IS NOT NULL,
    'Un signalement manuel doit être confirmé dès sa création';
  ASSERT (SELECT quantite_demandee FROM ruptures WHERE id = v_rupture) = 6,
    'La quantité demandée n''a pas été enregistrée';
  RAISE NOTICE '  ok  catalogue : un signalement manuel part sans confirmation';

  -- ── 11. Demander deux fois le même produit ne crée pas de doublon ───────
  SELECT id INTO v_autre FROM signaler_rupture(v_produit, 3);
  ASSERT v_autre = v_rupture,
    'Un second signalement du même produit devrait rendre la demande existante';

  SELECT count(*) INTO v_nb
    FROM ruptures WHERE point_de_vente_id = v_pdv AND produit_id = v_produit
                    AND statut = 'signalee';
  ASSERT v_nb = 1, format('1 rupture attendue pour ce produit, %s trouvée(s)', v_nb);
  RAISE NOTICE '  ok  catalogue : demander deux fois ne duplique pas la course';

  -- ── 12. Le catalogue montre ce que le boutiquier peut demander ──────────
  SELECT count(*) INTO v_nb FROM v_catalogue_point_de_vente
   WHERE point_de_vente_id = v_pdv;
  ASSERT v_nb > 0,
    'Le catalogue devrait exposer les produits des fabricants qui desservent la boutique';

  ASSERT EXISTS (
    SELECT 1 FROM v_catalogue_point_de_vente
     WHERE point_de_vente_id = v_pdv AND produit_id = v_produit AND deja_demande
  ), 'Le catalogue doit signaler un produit déjà demandé';
  RAISE NOTICE '  ok  catalogue : un produit déjà demandé est marqué comme tel';

  RAISE NOTICE '';
  RAISE NOTICE 'Confirmation et catalogue : tous les cas passent.';
END;
$test$;

ROLLBACK;
