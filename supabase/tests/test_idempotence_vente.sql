-- Une relance après timeout ne doit pas créer une seconde vente.
-- psql -v ON_ERROR_STOP=1 -d yalla -f supabase/tests/test_idempotence_vente.sql

BEGIN;

DO $test$
DECLARE
  v_pdv       UUID;
  v_produit   UUID;
  v_cle       UUID := gen_random_uuid();
  v_vente_1   UUID;
  v_vente_2   UUID;
  v_stock     INTEGER;
  v_nb        INTEGER;
BEGIN
  SELECT id INTO v_pdv FROM points_de_vente LIMIT 1;
  SELECT id INTO v_produit FROM produits WHERE disponible LIMIT 1;

  ASSERT v_pdv IS NOT NULL, 'Seed absent : aucun point de vente';
  ASSERT v_produit IS NOT NULL, 'Seed absent : aucun produit disponible';

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('user_role', 'point_de_vente', 'id_metier', v_pdv)::TEXT,
    true
  );

  INSERT INTO stocks (point_de_vente_id, produit_id, quantite)
  VALUES (v_pdv, v_produit, 10)
  ON CONFLICT (point_de_vente_id, produit_id) WHERE produit_id IS NOT NULL
  DO UPDATE SET quantite = 10, date_maj = now();

  SELECT id INTO v_vente_1
  FROM enregistrer_vente(
    jsonb_build_array(jsonb_build_object(
      'produit_id', v_produit,
      'quantite', 1,
      'prix_unitaire', 500
    )),
    v_cle
  );

  SELECT id INTO v_vente_2
  FROM enregistrer_vente(
    jsonb_build_array(jsonb_build_object(
      'produit_id', v_produit,
      'quantite', 1,
      'prix_unitaire', 500
    )),
    v_cle
  );

  ASSERT v_vente_1 = v_vente_2,
    'La seconde tentative doit renvoyer la vente initiale';

  SELECT quantite INTO v_stock
  FROM stocks
  WHERE point_de_vente_id = v_pdv AND produit_id = v_produit;
  ASSERT v_stock = 9,
    format('Le stock devrait diminuer une seule fois, trouvé %s', v_stock);

  SELECT count(*) INTO v_nb
  FROM ventes
  WHERE point_de_vente_id = v_pdv AND cle_operation = v_cle;
  ASSERT v_nb = 1,
    format('Une seule vente idempotente attendue, trouvé %s', v_nb);

  RAISE NOTICE 'Idempotence caisse : vente et stock protégés contre le double envoi.';
END;
$test$;

ROLLBACK;
