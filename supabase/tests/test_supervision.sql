-- test_supervision.sql
--
-- Ce que l'administrateur voit, ce qu'il peut faire, et surtout ce qu'il ne
-- doit pas voir.
--
--   psql -v ON_ERROR_STOP=1 -d yalla -f supabase/tests/test_supervision.sql
--
-- LE CAS LE PLUS IMPORTANT DE CE FICHIER est le dernier : l'administrateur ne
-- voit pas les ventes d'une boutique. C'est la promesse qui fait accepter la
-- caisse gratuite au boutiquier, et une promesse qui souffre une exception
-- pour l'exploitant n'en est plus une. Un élargissement de droits futur la
-- casserait sans bruit ; ce test l'empêche.
--
-- Tout se déroule dans une transaction close par ROLLBACK.

BEGIN;

DO $test$
DECLARE
  v_admin   UUID;
  v_pdv     UUID;
  v_dist    UUID;
  v_fab     UUID;
  v_nb      INTEGER;
  v_resultat JSONB;
  v_taux    NUMERIC;
BEGIN
  SELECT id INTO v_admin FROM utilisateurs WHERE role = 'administrateur' LIMIT 1;
  SELECT id INTO v_pdv   FROM points_de_vente LIMIT 1;
  SELECT id INTO v_dist  FROM distributeurs LIMIT 1;
  SELECT id INTO v_fab   FROM fabricants LIMIT 1;

  ASSERT v_admin IS NOT NULL, 'Seed absent : aucun administrateur';
  ASSERT v_pdv IS NOT NULL,   'Seed absent : aucun point de vente';

  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'administrateur',
                      'utilisateur_id', v_admin)::TEXT, true);

  -- ── 1. La vue d'ensemble rend quelque chose ──────────────────────────────
  SELECT boutiques_actives INTO v_nb FROM v_supervision_reseau;
  ASSERT v_nb IS NOT NULL, 'La vue de supervision ne rend rien à l''administrateur';
  RAISE NOTICE '  ok  supervision : l''administrateur voit l''état du réseau';

  -- ── 2. Les anomalies remontent ───────────────────────────────────────────
  -- On en fabrique une : une boutique active que personne ne dessert.
  INSERT INTO utilisateurs (nom, telephone, role)
  VALUES ('Gérant orphelin', '2250700888001', 'point_de_vente');

  INSERT INTO points_de_vente (nom, type_activite, commune, position, statut, utilisateur_id)
  VALUES ('Boutique sans distributeur', 'boutique', 'Yopougon',
          ST_SetSRID(ST_MakePoint(-4.08, 5.34), 4326)::GEOGRAPHY, 'actif',
          (SELECT id FROM utilisateurs WHERE telephone = '2250700888001'));

  SELECT count(*) INTO v_nb
    FROM v_anomalies_reseau
   WHERE type_anomalie = 'boutique_sans_distributeur'
     AND objet_nom = 'Boutique sans distributeur';
  ASSERT v_nb = 1, 'Une boutique sans distributeur devrait être signalée';
  RAISE NOTICE '  ok  anomalies : une boutique que personne ne dessert est repérée';

  -- Elle est aussi sans stock : la même boutique remonte deux fois, sur deux
  -- anomalies différentes, et c'est voulu. Ce sont deux problèmes distincts,
  -- avec deux corrections distinctes.
  SELECT count(*) INTO v_nb
    FROM v_anomalies_reseau
   WHERE type_anomalie = 'boutique_sans_stock'
     AND objet_nom = 'Boutique sans distributeur';
  ASSERT v_nb = 1, 'Une boutique sans stock suivi devrait être signalée';
  RAISE NOTICE '  ok  anomalies : une boutique sans stock suivi est repérée';

  -- ── 3. Attribuer une boutique ────────────────────────────────────────────
  -- C'est le geste qui débloque un distributeur qui démarre : sans lui, il ne
  -- voit aucune boutique et ne peut jamais commencer.
  IF v_dist IS NOT NULL AND v_fab IS NOT NULL THEN
    v_resultat := attribuer_boutique_admin(
      (SELECT id FROM points_de_vente WHERE nom = 'Boutique sans distributeur'),
      v_fab, v_dist);

    ASSERT v_resultat->>'boutique' = 'Boutique sans distributeur',
      'La fonction devrait rendre le nom de la boutique attribuée';

    SELECT count(*) INTO v_nb
      FROM v_anomalies_reseau
     WHERE type_anomalie = 'boutique_sans_distributeur'
       AND objet_nom = 'Boutique sans distributeur';
    ASSERT v_nb = 0, 'L''anomalie devrait avoir disparu après attribution';
    RAISE NOTICE '  ok  attribution : le geste fait disparaître l''anomalie';

    -- Reprendre une boutique à un confrère doit être dit : c'est une décision
    -- commerciale, et l'administrateur doit savoir qu'il la prend.
    IF EXISTS (SELECT 1 FROM distributeurs WHERE id <> v_dist) THEN
      v_resultat := attribuer_boutique_admin(
        (SELECT id FROM points_de_vente WHERE nom = 'Boutique sans distributeur'),
        v_fab,
        (SELECT id FROM distributeurs WHERE id <> v_dist LIMIT 1));

      ASSERT v_resultat->>'repris_a' IS NOT NULL,
        'La fonction devrait signaler à qui la boutique a été reprise';
      RAISE NOTICE '  ok  attribution : reprendre une boutique est signalé nommément';
    END IF;
  END IF;

  -- ── 4. Le taux de service du réseau est calculable ───────────────────────
  SELECT taux_de_service_pct INTO v_taux FROM v_supervision_reseau;
  -- Il peut être nul si aucune rupture n'est close : c'est un état valide, pas
  -- une erreur. Ce qui compte est qu'il ne soit jamais aberrant.
  ASSERT v_taux IS NULL OR (v_taux >= 0 AND v_taux <= 100),
    format('Taux de service hors bornes : %s', v_taux);
  RAISE NOTICE '  ok  indicateur : le taux de service du réseau tient dans ses bornes';

  -- ── 5. Un autre rôle ne peut pas attribuer ───────────────────────────────
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'distributeur', 'id_metier', v_dist)::TEXT, true);
  BEGIN
    PERFORM attribuer_boutique_admin(v_pdv, v_fab, v_dist);
    RAISE EXCEPTION 'Un distributeur a pu s''attribuer une boutique';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok  périmètre : seul l''administrateur attribue une boutique';
  END;

  -- ── 6. Valider une demande de fabricant crée bien la marque ──────────────
  --
  -- `creer_compte_metier` traitait quatre rôles sur cinq et laissait passer le
  -- cinquième SANS ERREUR, en rendant `id_metier: null`. Le compte se
  -- connectait et ne voyait rien, et aucun message ne l'expliquait. C'est le
  -- premier geste du tableau de bord administrateur : il doit tenir.
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'administrateur',
                      'utilisateur_id', v_admin)::TEXT, true);

  v_resultat := creer_compte_metier(
    NULL, 'Responsable marque', '2250700888777', 'fabricant',
    '{"nom_societe": "Brasserie d''essai"}'::JSONB);

  ASSERT v_resultat->>'id_metier' IS NOT NULL,
    'Un compte fabricant sans ligne métier : il se connectera et ne verra rien';

  SELECT count(*) INTO v_nb
    FROM fabricants WHERE nom = 'Brasserie d''essai';
  ASSERT v_nb = 1, 'La marque devrait exister en base après validation';
  RAISE NOTICE '  ok  validation : une demande de fabricant crée bien la marque';

  -- ── 7. Un fabricant ne voit que sa propre ligne ──────────────────────────
  --
  -- `v_tableau_de_bord_fabricant` partait de `fabricants`, lisible de tous les
  -- comptes parce que le boutiquier parcourt les catalogues, et n'ajoutait
  -- aucun filtre. Chaque fabricant voyait donc la ligne de ses concurrents.
  --
  -- Pire que la fuite : la page web lit `lignes[0]`. Avec deux fabricants en
  -- base, elle affichait à chacun le tableau de bord du premier venu, nom
  -- d'entreprise compris, sans la moindre erreur pour le signaler.
  --
  -- Ce test n'a de sens que parce qu'il existe maintenant au moins deux
  -- fabricants : celui du jeu de départ et celui créé au cas précédent.
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'fabricant',
                      'id_metier', v_resultat->>'id_metier')::TEXT, true);

  SELECT count(*) INTO v_nb FROM v_tableau_de_bord_fabricant;
  ASSERT v_nb = 1,
    format('Un fabricant voit %s ligne(s) : celles de ses concurrents comprises', v_nb);

  SELECT count(*) INTO v_nb
    FROM v_tableau_de_bord_fabricant WHERE fabricant_nom = 'Brasserie d''essai';
  ASSERT v_nb = 1, 'La ligne que voit le fabricant n''est pas la sienne';
  RAISE NOTICE '  ok  cloisonnement : un fabricant ne voit que sa propre ligne';

  -- ── 8. L'ADMINISTRATEUR NE VOIT PAS LA CAISSE ────────────────────────────
  --
  -- Le test le plus important du fichier. La promesse faite au boutiquier est
  -- que ses ventes n'appartiennent qu'à lui. Si un élargissement de droits
  -- futur la casse, c'est ici qu'on doit l'apprendre, pas sur le terrain.
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'administrateur',
                      'utilisateur_id', v_admin)::TEXT, true);

  -- Deux façons de ne rien voir, et les deux conviennent : soit les politiques
  -- ne rendent aucune ligne, soit le droit de table manque. Sur Supabase c'est
  -- la première qui s'applique, en local la seconde, le simulacre n'accordant
  -- pas les mêmes GRANT. Ce qui compte est le résultat, pas le mécanisme.
  SET LOCAL ROLE authenticated;

  BEGIN
    SELECT count(*) INTO v_nb FROM ventes;
    ASSERT v_nb = 0,
      format('L''administrateur voit %s vente(s) : la promesse faite au boutiquier est rompue', v_nb);

    SELECT count(*) INTO v_nb FROM lignes_vente;
    ASSERT v_nb = 0,
      format('L''administrateur voit %s ligne(s) de vente : la promesse est rompue', v_nb);
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  RESET ROLE;
  RAISE NOTICE '  ok  confidentialité : l''administrateur ne voit aucune vente';

  RAISE NOTICE '';
  RAISE NOTICE 'Supervision : tous les cas passent.';
END;
$test$;

ROLLBACK;
