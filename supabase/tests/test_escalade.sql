-- test_escalade.sql
--
-- Premier test automatisé du dépôt. Il vérifie par exécution le routage des
-- ruptures et la règle d'escalade introduits par la migration 011, contre une
-- vraie base PostgreSQL.
--
-- Il suppose la base provisionnée avec les migrations ET le seed de
-- développement (`supabase db reset`), puisqu'il s'appuie sur les acteurs
-- que le seed met en place : Distrib Cocody, Sahel Distribution, Superette
-- Akwaba et la rupture automatique déclenchée par la vente de jus.
--
--   psql -v ON_ERROR_STOP=1 -d yalla -f supabase/tests/test_escalade.sql
--
-- Le test ne laisse rien derrière lui : tout se déroule dans une transaction
-- qui se termine par ROLLBACK. Il est donc rejouable autant de fois que voulu
-- sur la même base, sans la repeupler.

BEGIN;

DO $test$
DECLARE
  v_rupture_id UUID;
  v_distributeur_attribue UUID;
  v_distributeur_voisin UUID;
  v_livreur_id UUID;
  v_livreur_voisin_user UUID;
  v_livreur_voisin UUID;
  v_nb INTEGER;
  v_cercle TEXT;
  v_statut TEXT;
  v_escaladees INTEGER;
  v_perimees INTEGER;
BEGIN
  SELECT id INTO v_distributeur_attribue FROM distributeurs WHERE nom = 'Distrib Cocody';
  SELECT id INTO v_distributeur_voisin FROM distributeurs WHERE nom = 'Sahel Distribution';
  SELECT id INTO v_livreur_id FROM livreurs WHERE distributeur_id = v_distributeur_attribue LIMIT 1;

  ASSERT v_distributeur_attribue IS NOT NULL, 'Seed absent : lancez supabase db reset';
  ASSERT v_distributeur_voisin IS NOT NULL, 'Seed absent : distributeur voisin manquant';
  ASSERT v_livreur_id IS NOT NULL, 'Seed absent : aucun livreur rattaché au distributeur';

  -- ── 1. La rupture automatique de la caisse a bien un destinataire ─────────
  -- C'est le test central : cette rupture est née d'un trigger SQL, elle n'est
  -- jamais passée par NestJS. Si le routage était codé côté application, ce
  -- distributeur_id serait NULL.
  SELECT id, statut INTO v_rupture_id, v_statut
  FROM ruptures WHERE signalement_automatique ORDER BY date_signalement DESC LIMIT 1;

  ASSERT v_rupture_id IS NOT NULL,
    'Le trigger de caisse n''a pas créé de rupture automatique';
  ASSERT v_statut = 'signalee',
    format('Rupture automatique attendue en signalee, trouvée %s', v_statut);

  ASSERT (SELECT distributeur_id FROM ruptures WHERE id = v_rupture_id) = v_distributeur_attribue,
    'La rupture automatique n''a pas été routée vers le distributeur attribué';

  RAISE NOTICE '  ok  routage automatique : la rupture de caisse est adressée au bon distributeur';

  -- ── 2. Avant escalade, seul le distributeur attribué y a accès ────────────
  SELECT count(*) INTO v_nb FROM v_acces_rupture_distributeur WHERE rupture_id = v_rupture_id;
  ASSERT v_nb = 1, format('Avant escalade : 1 accès attendu, %s trouvé(s)', v_nb);

  SELECT cercle INTO v_cercle FROM v_acces_rupture_distributeur WHERE rupture_id = v_rupture_id;
  ASSERT v_cercle = 'attribue', format('Cercle attendu attribue, trouvé %s', v_cercle);

  RAISE NOTICE '  ok  cercle fermé : le distributeur voisin ne voit rien avant le délai';

  -- ── 3. Rien ne s'escalade avant l'échéance ───────────────────────────────
  SELECT count(*) INTO v_escaladees FROM escalader_ruptures_en_attente();
  ASSERT v_escaladees = 0,
    format('Une rupture fraîche ne doit pas s''escalader, %s action(s) déclenchée(s)', v_escaladees);

  RAISE NOTICE '  ok  patience : aucune escalade avant les deux heures';

  -- ── 4. Passé le délai, la rupture s'ouvre au cercle élargi ───────────────
  UPDATE ruptures SET date_signalement = now() - INTERVAL '3 hours' WHERE id = v_rupture_id;

  SELECT count(*) INTO v_escaladees
  FROM escalader_ruptures_en_attente() WHERE action = 'escaladee';
  ASSERT v_escaladees = 1, format('1 escalade attendue, %s obtenue(s)', v_escaladees);

  SELECT count(*) INTO v_nb FROM v_acces_rupture_distributeur WHERE rupture_id = v_rupture_id;
  ASSERT v_nb = 2, format('Après escalade : 2 accès attendus, %s trouvé(s)', v_nb);

  ASSERT EXISTS (
    SELECT 1 FROM v_acces_rupture_distributeur
    WHERE rupture_id = v_rupture_id
      AND distributeur_id = v_distributeur_voisin
      AND cercle = 'elargi'
  ), 'Le distributeur voisin de la commune devrait voir la rupture après escalade';

  RAISE NOTICE '  ok  escalade : la rupture s''ouvre au distributeur voisin de la commune';

  -- ── 5. L'escalade est idempotente ────────────────────────────────────────
  -- Le job tourne toutes les 5 minutes : une rupture déjà escaladée ne doit pas
  -- être réescaladée à chaque passage, sinon chaque passe renotifierait tout le
  -- monde.
  SELECT count(*) INTO v_escaladees
  FROM escalader_ruptures_en_attente() WHERE action = 'escaladee';
  ASSERT v_escaladees = 0,
    format('Réescalade interdite, %s action(s) obtenue(s) au second passage', v_escaladees);

  RAISE NOTICE '  ok  idempotence : une seconde passe ne réescalade rien';

  -- ── 6. Un livreur du distributeur voisin peut prendre la course ──────────
  INSERT INTO utilisateurs (nom, telephone, role)
  VALUES ('Test Livreur Voisin', '+2250799999999', 'livreur')
  RETURNING id INTO v_livreur_voisin_user;

  INSERT INTO livreurs (utilisateur_id, distributeur_id, en_ligne)
  VALUES (v_livreur_voisin_user, v_distributeur_voisin, true)
  RETURNING id INTO v_livreur_voisin;

  UPDATE ruptures r
  SET statut = 'prise_en_charge', livreur_id = l.id, date_prise_en_charge = now()
  FROM livreurs l
  WHERE r.id = v_rupture_id AND l.id = v_livreur_voisin AND r.statut = 'signalee'
    AND EXISTS (
      SELECT 1 FROM v_acces_rupture_distributeur acc
      WHERE acc.rupture_id = r.id AND acc.distributeur_id = l.distributeur_id
    );
  GET DIAGNOSTICS v_nb = ROW_COUNT;
  ASSERT v_nb = 1, 'Le livreur du distributeur élargi aurait dû pouvoir prendre la course';

  RAISE NOTICE '  ok  prise en charge : un livreur du cercle élargi obtient la course';

  -- ── 7. Un second livreur ne peut pas la reprendre ────────────────────────
  -- C'est le correctif de concurrence. Avant la 011, cet UPDATE réussissait et
  -- deux livreurs partaient sur la même course.
  UPDATE ruptures r
  SET statut = 'prise_en_charge', livreur_id = l.id, date_prise_en_charge = now()
  FROM livreurs l
  WHERE r.id = v_rupture_id AND l.id = v_livreur_id AND r.statut = 'signalee'
    AND EXISTS (
      SELECT 1 FROM v_acces_rupture_distributeur acc
      WHERE acc.rupture_id = r.id AND acc.distributeur_id = l.distributeur_id
    );
  GET DIAGNOSTICS v_nb = ROW_COUNT;
  ASSERT v_nb = 0, 'Second preneur : l''UPDATE aurait dû ne toucher aucune ligne';

  ASSERT (SELECT livreur_id FROM ruptures WHERE id = v_rupture_id) = v_livreur_voisin,
    'Le preneur enregistré doit rester le premier arrivé';

  RAISE NOTICE '  ok  concurrence : le second livreur repart les mains vides';

  -- ── 8. Péremption ────────────────────────────────────────────────────────
  -- On repart d'une rupture libre et très ancienne.
  UPDATE ruptures
  SET statut = 'signalee', livreur_id = NULL, date_prise_en_charge = NULL,
      date_signalement = now() - INTERVAL '30 hours'
  WHERE id = v_rupture_id;

  SELECT count(*) INTO v_perimees
  FROM escalader_ruptures_en_attente() WHERE action = 'perimee';
  ASSERT v_perimees = 1, format('1 péremption attendue, %s obtenue(s)', v_perimees);

  SELECT statut INTO v_statut FROM ruptures WHERE id = v_rupture_id;
  ASSERT v_statut = 'non_servie',
    format('Statut attendu non_servie, trouvé %s', v_statut);

  ASSERT (SELECT date_resolution FROM ruptures WHERE id = v_rupture_id) IS NOT NULL,
    'Une rupture périmée doit être horodatée comme close';

  RAISE NOTICE '  ok  péremption : la rupture abandonnée est close en non_servie';

  -- ── 9. Une rupture close sort des listes et entre dans le taux de service ─
  SELECT count(*) INTO v_nb FROM v_acces_rupture_distributeur WHERE rupture_id = v_rupture_id;
  ASSERT v_nb = 0, 'Une rupture périmée ne doit plus apparaître dans les accès';

  SELECT count(*) INTO v_nb FROM v_ruptures_ouvertes WHERE rupture_id = v_rupture_id;
  ASSERT v_nb = 0, 'Une rupture périmée ne doit plus apparaître dans les ruptures ouvertes';

  ASSERT EXISTS (SELECT 1 FROM v_taux_de_service_par_fabricant),
    'Le taux de service doit devenir calculable dès qu''une rupture est close';

  RAISE NOTICE '  ok  taux de service : la rupture non servie est comptabilisée';

  -- ── 10. Les trois cas de terrain tiennent dans le modèle ─────────────────
  ASSERT (SELECT count(*) FROM distributeurs WHERE fabricant_id IS NOT NULL AND NOT auto_distribution) > 0,
    'Cas 1 non représenté : distributeur affilié à un fabricant';

  INSERT INTO distributeurs (nom, telephone) VALUES ('Test Indépendant', '+2250799999998');
  ASSERT (SELECT count(*) FROM distributeurs WHERE fabricant_id IS NULL) = 1,
    'Cas 2 non représenté : un distributeur indépendant doit pouvoir exister sans fabricant';

  INSERT INTO distributeurs (fabricant_id, nom, auto_distribution)
  SELECT id, nom || ' (distribution interne)', true FROM fabricants LIMIT 1;
  ASSERT (SELECT count(*) FROM distributeurs WHERE auto_distribution) = 1,
    'Cas 3 non représenté : auto-distribution d''un fabricant';

  RAISE NOTICE '  ok  modèle : les trois cas de terrain sont représentables';

  RAISE NOTICE '';
  RAISE NOTICE 'Tous les tests d''escalade passent.';
END
$test$;

-- Rien n'est conservé : le test est rejouable à l'identique.
ROLLBACK;
