-- test_livraison.sql
--
-- Le cycle complet d'une course : prise, abandon, reprise, livraison.
--
-- Ce test est le premier à **simuler une identité** en posant
-- `request.jwt.claims`, comme le fait Supabase à chaque requête. Il vérifie donc
-- au passage `auth_role()` et `auth_id_metier()`, dont dépendent toutes les
-- politiques RLS et toutes les fonctions métier.
--
--   psql -v ON_ERROR_STOP=1 -d yalla -f supabase/tests/test_livraison.sql
--
-- Tout se déroule dans une transaction close par ROLLBACK : rejouable à volonté.

BEGIN;

DO $test$
DECLARE
  v_livreur_id   UUID;
  v_rupture_id   UUID;
  v_livraison_id UUID;
  v_statut       TEXT;
  v_nb           INTEGER;
  v_montant      NUMERIC;
  v_escaladee    TIMESTAMPTZ;
BEGIN
  SELECT l.id INTO v_livreur_id FROM livreurs l LIMIT 1;
  SELECT id INTO v_rupture_id FROM ruptures WHERE statut = 'signalee' LIMIT 1;

  ASSERT v_livreur_id IS NOT NULL, 'Seed absent : lancez supabase db reset';
  ASSERT v_rupture_id IS NOT NULL, 'Aucune rupture ouverte dans le seed';

  -- On se fait passer pour ce livreur, exactement comme le ferait un jeton
  -- émis par Supabase après passage du hook.
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'livreur', 'id_metier', v_livreur_id)::TEXT, true);

  ASSERT auth_role() = 'livreur', 'auth_role() ne lit pas le jeton simulé';
  ASSERT auth_id_metier() = v_livreur_id, 'auth_id_metier() ne lit pas le jeton simulé';
  RAISE NOTICE '  ok  identité : le rôle et l''ID métier sont lus dans le jeton';

  -- ── 1. Prendre une course crée la livraison ──────────────────────────────
  SELECT id INTO v_livraison_id FROM prendre_rupture(v_rupture_id);
  ASSERT v_livraison_id IS NOT NULL, 'prendre_rupture() n''a pas rendu de livraison';

  SELECT statut INTO v_statut FROM livraisons WHERE id = v_livraison_id;
  ASSERT v_statut = 'en_cours', format('Livraison attendue en_cours, trouvée %s', v_statut);

  SELECT statut INTO v_statut FROM ruptures WHERE id = v_rupture_id;
  ASSERT v_statut = 'prise_en_charge',
    format('Rupture attendue prise_en_charge, trouvée %s', v_statut);

  RAISE NOTICE '  ok  prise : la livraison est créée dans la même transaction';

  -- ── 2. Une course déjà prise ne se reprend pas ───────────────────────────
  BEGIN
    PERFORM prendre_rupture(v_rupture_id);
    RAISE EXCEPTION 'Une course déjà prise a pu être reprise';
  EXCEPTION WHEN lock_not_available THEN
    RAISE NOTICE '  ok  concurrence : le second preneur est refusé';
  END;

  -- ── 3. Abandonner remet la rupture en circulation ────────────────────────
  -- C'est le point qui manquait : sans cela, une panne de moto retirait la
  -- rupture du circuit pour toujours.
  PERFORM annuler_livraison(v_livraison_id);

  SELECT statut INTO v_statut FROM livraisons WHERE id = v_livraison_id;
  ASSERT v_statut = 'annulee', format('Livraison attendue annulee, trouvée %s', v_statut);

  SELECT statut, escaladee_le INTO v_statut, v_escaladee FROM ruptures WHERE id = v_rupture_id;
  ASSERT v_statut = 'signalee',
    format('Après abandon, rupture attendue signalee, trouvée %s', v_statut);
  ASSERT v_escaladee IS NULL, 'Le compte à rebours d''escalade devrait repartir de zéro';
  ASSERT (SELECT livreur_id FROM ruptures WHERE id = v_rupture_id) IS NULL,
    'Le livreur devrait être détaché de la rupture abandonnée';

  RAISE NOTICE '  ok  abandon : la rupture repart, le délai d''escalade est remis à zéro';

  -- ── 4. Reprendre, puis livrer ────────────────────────────────────────────
  SELECT id INTO v_livraison_id FROM prendre_rupture(v_rupture_id);
  PERFORM terminer_livraison(v_livraison_id, 18000);

  SELECT statut, montant INTO v_statut, v_montant FROM livraisons WHERE id = v_livraison_id;
  ASSERT v_statut = 'terminee', format('Livraison attendue terminee, trouvée %s', v_statut);
  ASSERT v_montant = 18000, format('Montant attendu 18000, trouvé %s', v_montant);

  -- Le trigger de la migration 005 clôt la rupture quand la livraison se termine.
  SELECT statut INTO v_statut FROM ruptures WHERE id = v_rupture_id;
  ASSERT v_statut = 'resolue',
    format('La livraison aurait dû clore la rupture, statut trouvé %s', v_statut);

  RAISE NOTICE '  ok  livraison : la rupture est close par le trigger, sans code applicatif';

  -- ── 5. L'encaissement est tracé ──────────────────────────────────────────
  SELECT count(*) INTO v_nb FROM transactions WHERE livraison_id = v_livraison_id;
  ASSERT v_nb = 1, format('1 transaction attendue, %s trouvée(s)', v_nb);
  ASSERT (SELECT fournisseur::TEXT FROM transactions WHERE livraison_id = v_livraison_id) = 'especes',
    'Le règlement du MVP doit être tracé en espèces';

  RAISE NOTICE '  ok  encaissement : le montant est tracé, en espèces';

  -- ── 6. On ne termine pas la livraison d'un autre ─────────────────────────
  BEGIN
    PERFORM set_config('request.jwt.claims',
      json_build_object('user_role', 'livreur',
                        'id_metier', gen_random_uuid())::TEXT, true);
    PERFORM terminer_livraison(v_livraison_id, 5000);
    RAISE EXCEPTION 'Un livreur a pu clore la livraison d''un autre';
  EXCEPTION WHEN no_data_found THEN
    RAISE NOTICE '  ok  propriété : un livreur ne clôt que ses propres courses';
  END;

  -- ── 7. Un rôle qui n'est pas livreur ne prend rien ───────────────────────
  BEGIN
    PERFORM set_config('request.jwt.claims',
      json_build_object('user_role', 'point_de_vente',
                        'id_metier', gen_random_uuid())::TEXT, true);
    PERFORM prendre_rupture(v_rupture_id);
    RAISE EXCEPTION 'Un point de vente a pu prendre une course';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok  rôle : seul un livreur peut prendre une course';
  END;

  RAISE NOTICE '';
  RAISE NOTICE 'Tous les tests du cycle de livraison passent.';
END
$test$;

ROLLBACK;
