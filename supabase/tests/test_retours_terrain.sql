-- Les retours terrain restent dans le périmètre boutique, fabricant et
-- distributeur attribué, sans ouvrir les ventes ni le stock.
-- Exécuté par supabase/tests/verifier-migrations.sh.

BEGIN;

DO $test$
DECLARE
  v_pdv UUID;
  v_fabricant UUID;
  v_distributeur UUID;
  v_produit UUID;
  v_retour retours_terrain;
  v_nombre INTEGER;
BEGIN
  SELECT ar.point_de_vente_id, ar.fabricant_id, ar.distributeur_id, p.id
    INTO v_pdv, v_fabricant, v_distributeur, v_produit
    FROM attributions_reseau ar
    JOIN produits p ON p.fabricant_id = ar.fabricant_id AND p.disponible
   WHERE ar.distributeur_id IS NOT NULL
   LIMIT 1;

  ASSERT v_pdv IS NOT NULL, 'Seed absent : aucune boutique attribuée';
  ASSERT v_produit IS NOT NULL, 'Seed absent : aucun produit disponible';

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'point_de_vente', 'id_metier', v_pdv)::TEXT, true);

  SELECT count(*) INTO v_nombre
    FROM v_destinataires_retours
   WHERE destinataire_role = 'fabricant' AND destinataire_id = v_fabricant;
  ASSERT v_nombre = 1, 'La boutique ne voit pas le fabricant de son catalogue';

  v_retour := envoyer_retour_terrain(
    'fabricant', v_fabricant, v_produit, 'qualite', 'Emballage souvent abîmé à la réception.'
  );
  ASSERT v_retour.id IS NOT NULL, 'Le retour terrain aurait dû être créé';

  SELECT count(*) INTO v_nombre FROM v_mes_retours_terrain WHERE retour_id = v_retour.id;
  ASSERT v_nombre = 1, 'La boutique doit retrouver son retour dans son historique';
  RAISE NOTICE '  ok  envoi et historique boutique';

  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'fabricant', 'id_metier', v_fabricant)::TEXT, true);
  SELECT count(*) INTO v_nombre FROM v_retours_terrain_recus WHERE retour_id = v_retour.id;
  ASSERT v_nombre = 1, 'Le fabricant concerné doit recevoir le retour';
  RAISE NOTICE '  ok  lecture par le fabricant destinataire';

  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'point_de_vente', 'id_metier', v_pdv)::TEXT, true);
  v_retour := envoyer_retour_terrain(
    'distributeur', v_distributeur, v_produit, 'livraison', 'Les livraisons arrivent souvent après la fermeture.'
  );
  ASSERT v_retour.id IS NOT NULL, 'Le retour au distributeur attribué aurait dû être créé';

  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'distributeur', 'id_metier', v_distributeur)::TEXT, true);
  SELECT count(*) INTO v_nombre FROM v_retours_terrain_recus WHERE retour_id = v_retour.id;
  ASSERT v_nombre = 1, 'Le distributeur attribué doit recevoir le retour';
  RAISE NOTICE '  ok  envoi et lecture par le distributeur attribué';

  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'fabricant', 'id_metier', gen_random_uuid())::TEXT, true);
  SELECT count(*) INTO v_nombre FROM v_retours_terrain_recus;
  ASSERT v_nombre = 0, 'Un autre fabricant ne doit voir aucun retour';
  RAISE NOTICE '  ok  cloisonnement entre fabricants';

  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'point_de_vente', 'id_metier', v_pdv)::TEXT, true);
  BEGIN
    PERFORM envoyer_retour_terrain(
      'fabricant', NULL, v_produit, 'qualite', 'Message sans fabricant destinataire.'
    );
    RAISE EXCEPTION 'Un retour fabricant sans destinataire a été accepté';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok  identifiant fabricant obligatoire';
  END;

  BEGIN
    PERFORM envoyer_retour_terrain(
      'fabricant', gen_random_uuid(), v_produit, 'qualite', 'Message vers une marque étrangère.'
    );
    RAISE EXCEPTION 'Une boutique a pu contacter un fabricant non attribué';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok  un fabricant non attribué est refusé';
  END;

  BEGIN
    PERFORM envoyer_retour_terrain(
      'distributeur', gen_random_uuid(), v_produit, 'livraison', 'Message vers un distributeur étranger.'
    );
    RAISE EXCEPTION 'Une boutique a pu contacter un distributeur non attribué';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok  un distributeur non attribué est refusé';
  END;

  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'distributeur', 'id_metier', v_distributeur)::TEXT, true);
  BEGIN
    PERFORM envoyer_retour_terrain(
      'distributeur', v_distributeur, v_produit, 'livraison', 'Un distributeur ne peut pas envoyer un retour boutique.'
    );
    RAISE EXCEPTION 'Un distributeur a pu envoyer un retour au nom d''une boutique';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok  seuls les points de vente peuvent émettre un retour';
  END;

  RESET ROLE;
END;
$test$;

ROLLBACK;