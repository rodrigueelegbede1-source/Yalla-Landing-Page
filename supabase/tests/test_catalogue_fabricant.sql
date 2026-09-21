-- test_catalogue_fabricant.sql
--
-- Le fabricant écrit sur son catalogue, et sur aucun autre.
--
--   psql -v ON_ERROR_STOP=1 -d yalla -f supabase/tests/test_catalogue_fabricant.sql
--
-- LE CAS QUI PORTE TOUT CE FICHIER est le dernier : un fabricant ne doit pas
-- pouvoir modifier le produit d'un concurrent, même en se l'attribuant au
-- passage. C'est le piège classique d'une politique d'UPDATE dont seul le
-- `WITH CHECK` filtre : la ligne visée n'est pas protégée, seule la ligne
-- obtenue l'est, et se réattribuer le produit d'un autre satisfait les deux.
--
-- Ces cas tournent SOUS LE RÔLE `authenticated`, sans quoi le propriétaire de
-- la base contournerait les politiques et le fichier entier passerait au vert
-- en ne vérifiant rien.
--
-- Tout se déroule dans une transaction close par ROLLBACK.

BEGIN;

DO $test$
DECLARE
  v_fab_a    UUID;
  v_fab_b    UUID;
  v_resultat JSONB;
  v_nb       INTEGER;
  v_ref      TEXT;
  v_produit  UUID;
  v_concurrent UUID;
BEGIN
  SELECT id INTO v_fab_a FROM fabricants ORDER BY created_at LIMIT 1;
  ASSERT v_fab_a IS NOT NULL, 'Seed absent : aucun fabricant';

  -- Un second fabricant, pour avoir un concurrent à ne pas toucher.
  INSERT INTO utilisateurs (nom, telephone, role)
  VALUES ('Concurrent', '2250700666001', 'fabricant');
  INSERT INTO fabricants (utilisateur_id, nom)
  VALUES ((SELECT id FROM utilisateurs WHERE telephone = '2250700666001'), 'Marque Concurrente')
  RETURNING id INTO v_fab_b;

  INSERT INTO produits (fabricant_id, nom, reference)
  VALUES (v_fab_b, 'Produit du concurrent', 'CONC-001')
  RETURNING id INTO v_concurrent;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'fabricant', 'id_metier', v_fab_a)::TEXT, true);

  -- ── 1. Créer un produit, référence fabriquée ─────────────────────────────
  -- Aucun fabricant du pilote n'a fourni ses références carton. Les inventer à
  -- la main produit des doublons et des fautes de frappe.
  v_resultat := enregistrer_produit('Huile de palme 1L', 'Epicerie');
  v_ref := v_resultat->>'reference';

  ASSERT (v_resultat->>'cree')::BOOLEAN, 'Le produit devrait être créé';
  ASSERT v_ref IS NOT NULL AND length(v_ref) > 3,
    format('Référence fabriquée illisible : « %s »', v_ref);
  ASSERT v_ref ~ '^[A-Z0-9-]+$',
    format('Une référence doit rester lisible sur un bon de livraison : « %s »', v_ref);
  RAISE NOTICE '  ok  catalogue : un produit se crée avec une référence lisible (%)', v_ref;

  -- ── 2. Deux formats du même produit ne se heurtent pas ───────────────────
  v_resultat := enregistrer_produit('Huile de palme 1L', 'Epicerie');
  ASSERT v_resultat->>'reference' <> v_ref,
    'Deux produits homonymes reçoivent la même référence : le second serait perdu';
  RAISE NOTICE '  ok  catalogue : une référence déjà prise est contournée';

  -- ── 3. La catégorie se crée, sans doublon de casse ───────────────────────
  PERFORM enregistrer_produit('Sel fin 500g', 'EPICERIE');
  SELECT count(*) INTO v_nb FROM categories_produit WHERE lower(nom) = 'epicerie';
  ASSERT v_nb = 1,
    format('« Epicerie » et « EPICERIE » ont produit %s catégories', v_nb);
  RAISE NOTICE '  ok  catalogue : la casse ne dédouble pas une catégorie';

  -- ── 4. Une référence explicite en double est refusée ─────────────────────
  BEGIN
    PERFORM enregistrer_produit('Autre produit', NULL, v_ref);
    RAISE EXCEPTION 'Une référence déjà prise a été acceptée';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE '  ok  catalogue : une référence en double est refusée lisiblement';
  END;

  -- ── 5. Retirer un produit sans rien détruire ─────────────────────────────
  -- Une suppression emporterait par cascade les ruptures et les stocks qui le
  -- référencent : l'historique du réseau disparaîtrait pour cause de ménage.
  SELECT produit_id INTO v_produit FROM v_mon_catalogue WHERE reference = v_ref;
  PERFORM enregistrer_produit('Huile de palme 1L', NULL, NULL, v_produit, false);

  SELECT count(*) INTO v_nb
    FROM v_mon_catalogue WHERE produit_id = v_produit AND NOT disponible;
  ASSERT v_nb = 1, 'Le produit devrait être retiré sans être supprimé';
  RAISE NOTICE '  ok  catalogue : un produit se retire sans perdre son historique';

  -- ── 6. Il ne voit que son catalogue ──────────────────────────────────────
  SELECT count(*) INTO v_nb FROM v_mon_catalogue WHERE reference = 'CONC-001';
  ASSERT v_nb = 0, 'Le catalogue d''un concurrent apparaît dans le sien';
  RAISE NOTICE '  ok  cloisonnement : le catalogue d''un concurrent reste invisible';

  -- ── 7. IL NE PEUT PAS MODIFIER LE PRODUIT D'UN CONCURRENT ────────────────
  --
  -- Le cas le plus important du fichier. Par la fonction, puis en direct, et
  -- surtout EN SE L'ATTRIBUANT : c'est cette dernière forme qui passerait si la
  -- politique d'UPDATE n'avait qu'un `WITH CHECK`.
  BEGIN
    PERFORM enregistrer_produit('Detourne', NULL, NULL, v_concurrent, true);
    RAISE EXCEPTION 'Un fabricant a modifié le produit d''un concurrent';
  EXCEPTION WHEN no_data_found THEN
    NULL;
  END;

  UPDATE produits SET nom = 'Detourne' WHERE id = v_concurrent;
  GET DIAGNOSTICS v_nb = ROW_COUNT;
  ASSERT v_nb = 0, 'Un fabricant a modifié en direct le produit d''un concurrent';

  UPDATE produits SET fabricant_id = v_fab_a, nom = 'Vole' WHERE id = v_concurrent;
  GET DIAGNOSTICS v_nb = ROW_COUNT;
  ASSERT v_nb = 0,
    'Un fabricant s''est approprié le produit d''un concurrent en se l''attribuant';
  RAISE NOTICE '  ok  cloisonnement : le produit d''un concurrent est intouchable';

  -- ── 8. IL VOIT OÙ SES PRODUITS MANQUENT ──────────────────────────────────
  --
  -- Le défaut le plus coûteux trouvé sur ce rôle : le fabricant avait accès à
  -- ses ruptures mais pas aux points de vente, et toutes les vues joignent les
  -- deux. Une jointure interne sur une table dont RLS ne rend rien supprime la
  -- ligne entière : il ne voyait pas « une rupture sans nom de boutique », il
  -- ne voyait rien du tout. Aucune erreur, un tableau vide, et la promesse
  -- centrale du produit annulée en silence.
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'fabricant', 'id_metier', v_fab_a)::TEXT, true);

  SELECT produit_id INTO v_produit FROM v_mon_catalogue WHERE disponible LIMIT 1;

  RESET ROLE;
  INSERT INTO ruptures (point_de_vente_id, produit_id, statut, confirmee_le)
  VALUES ((SELECT id FROM points_de_vente WHERE statut = 'actif' LIMIT 1),
          v_produit, 'signalee', now());
  SET LOCAL ROLE authenticated;

  SELECT count(*) INTO v_nb FROM v_mes_ruptures WHERE produit_id = v_produit;
  ASSERT v_nb >= 1,
    'Le fabricant ne voit aucune de ses ruptures : la jointure au point de vente les efface';

  SELECT count(*) INTO v_nb
    FROM v_mes_ruptures WHERE produit_id = v_produit AND point_de_vente IS NOT NULL;
  ASSERT v_nb >= 1,
    'La rupture remonte sans le nom de la boutique : le fabricant ne sait pas où aller';
  RAISE NOTICE '  ok  fabricant : il voit ses ruptures ET où elles sont';

  -- Il ne voit pas pour autant tout le réseau. La liste des points de vente
  -- d'Abidjan est un actif commercial ; la donner à chaque marque revient à la
  -- publier.
  RESET ROLE;
  INSERT INTO utilisateurs (nom, telephone, role)
  VALUES ('Gerant etranger', '2250700666002', 'point_de_vente');
  INSERT INTO points_de_vente (nom, type_activite, commune, position, statut, utilisateur_id)
  VALUES ('Boutique sans lien', 'boutique', 'Bingerville',
          ST_SetSRID(ST_MakePoint(-3.89, 5.35), 4326)::GEOGRAPHY, 'actif',
          (SELECT id FROM utilisateurs WHERE telephone = '2250700666002'));
  SET LOCAL ROLE authenticated;

  SELECT count(*) INTO v_nb
    FROM points_de_vente WHERE nom = 'Boutique sans lien';
  ASSERT v_nb = 0,
    'Le fabricant voit une boutique qui ne porte pas sa marque et n''a aucune de ses ruptures';
  RAISE NOTICE '  ok  cloisonnement : il ne voit pas le réseau des autres';

  -- ── 9. Un autre rôle n'écrit pas au catalogue ────────────────────────────
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'distributeur', 'id_metier', v_fab_a)::TEXT, true);
  BEGIN
    PERFORM enregistrer_produit('Produit pirate', NULL);
    RAISE EXCEPTION 'Un distributeur a pu écrire au catalogue';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok  périmètre : seul un fabricant écrit à son catalogue';
  END;

  RESET ROLE;

  RAISE NOTICE '';
  RAISE NOTICE 'Catalogue fabricant : tous les cas passent.';
END;
$test$;

ROLLBACK;
