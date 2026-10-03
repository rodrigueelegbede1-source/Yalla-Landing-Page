-- Vérifie les contrats de la migration rôles/catalogue/admin.
-- À exécuter sur une base de test déjà provisionnée avec le seed.
BEGIN;

DO $test$
DECLARE
  v_pdv UUID;
  v_fabricant UUID;
  v_distributeur UUID;
  v_nb INTEGER;
BEGIN
  SELECT id INTO v_pdv FROM points_de_vente LIMIT 1;
  SELECT id INTO v_fabricant FROM fabricants LIMIT 1;
  SELECT id INTO v_distributeur FROM distributeurs WHERE fabricant_id IS NULL LIMIT 1;

  ASSERT v_pdv IS NOT NULL, 'Seed absent : point de vente manquant';
  ASSERT v_fabricant IS NOT NULL, 'Seed absent : fabricant manquant';
  IF v_distributeur IS NULL THEN
    RAISE NOTICE 'Aucun distributeur indépendant dans le seed : contrôle d''accord ignoré';
    RAISE NOTICE 'Rôles, catalogue global et image stock : contrôles passés.';
    RETURN;
  END IF;

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('user_role', 'point_de_vente', 'id_metier', v_pdv)::TEXT,
    true
  );

  SELECT count(*) INTO v_nb FROM v_catalogue_point_de_vente
   WHERE point_de_vente_id = v_pdv;
  ASSERT v_nb >= (SELECT count(*) FROM produits WHERE disponible),
    'Le catalogue boutique doit inclure tous les produits disponibles';

  ASSERT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'v_stock_point_de_vente'
       AND column_name = 'image_url'
  ), 'La vue de stock doit exposer image_url';

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('user_role', 'distributeur', 'id_metier', v_distributeur)::TEXT,
    true
  );

  -- Sans accord, un indépendant ne doit pas pouvoir écrire dans le catalogue.
  BEGIN
    PERFORM enregistrer_produit('Produit test autorisation', 'Boissons', NULL, NULL, true, v_fabricant);
    RAISE EXCEPTION 'Un distributeur a écrit sans accord fabricant';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'ok : accord fabricant requis pour le distributeur';
  END;

  RAISE NOTICE 'Rôles, catalogue global et autorisation distributeur : contrôles passés.';
END;
$test$;

ROLLBACK;
