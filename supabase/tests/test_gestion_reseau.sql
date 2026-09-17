-- test_gestion_reseau.sql
--
-- La création de comptes, la flotte et la revendication de boutiques.
--
--   psql -v ON_ERROR_STOP=1 -d yalla -f supabase/tests/test_gestion_reseau.sql
--
-- CE QUE CE FICHIER SURVEILLE EN PRIORITÉ : les refus. Une fonction de création
-- de comptes qui marche est facile à écrire ; une qui refuse exactement ce
-- qu'elle doit refuser l'est moins, et c'est elle qui décide si un agent
-- recenseur peut se fabriquer un compte administrateur.
--
-- Tout se déroule dans une transaction close par ROLLBACK : rejouable à volonté.

BEGIN;

-- Un compte de connexion jetable.
--
-- `utilisateurs.auth_user_id` porte une clé étrangère vers `auth.users` : la
-- ligne métier ne peut pas exister avant le compte de connexion. C'est
-- exactement pourquoi la fonction Edge crée le compte D'ABORD, puis appelle
-- `creer_compte_metier`, et supprime le compte si celle-ci refuse. Le test
-- reproduit cet ordre plutôt que de le contourner.
--
-- Dans `pg_temp` : la fonction disparaît avec la session, et n'a donc aucune
-- chance de se retrouver en production.
CREATE FUNCTION pg_temp.compte_auth() RETURNS UUID
LANGUAGE sql AS $fn$
  INSERT INTO auth.users (id) VALUES (gen_random_uuid()) RETURNING id;
$fn$;

DO $test$
DECLARE
  v_agent_id    UUID;
  v_distrib_id  UUID;
  v_autre_dist  UUID;
  v_fabricant   UUID;
  v_autre_fab   UUID;
  v_pdv_id      UUID;
  v_livreur_id  UUID;
  v_faux_auth   UUID;
  v_resultat    JSONB;
  v_nb          INTEGER;
  v_actif       BOOLEAN;
  v_communes    TEXT[];
  v_scratch     UUID;
BEGIN
  SELECT a.id INTO v_agent_id FROM agents_recenseurs a LIMIT 1;
  SELECT f.id INTO v_fabricant FROM fabricants f LIMIT 1;
  SELECT pdv.id INTO v_pdv_id FROM points_de_vente pdv LIMIT 1;

  ASSERT v_agent_id  IS NOT NULL, 'Seed absent : aucun agent recenseur';
  ASSERT v_fabricant IS NOT NULL, 'Seed absent : aucun fabricant';
  ASSERT v_pdv_id    IS NOT NULL, 'Seed absent : aucun point de vente';

  -- Le test fabrique ce dont il a besoin plutôt que de le chercher dans le
  -- seed. Les deux distributeurs du seed sont affiliés au même fabricant, et
  -- une première version de ce fichier échouait faute de distributeur
  -- indépendant. Un test qui dépend de la forme du seed casse dès qu'on
  -- l'enrichit, et son échec ne dit rien du code testé.
  INSERT INTO utilisateurs (nom, telephone, role)
  VALUES ('Indépendant du test', '2250700999001', 'distributeur')
  RETURNING id INTO v_scratch;

  INSERT INTO distributeurs (utilisateur_id, fabricant_id, nom, telephone)
  VALUES (v_scratch, NULL, 'Indépendant du test', '2250700999001')
  RETURNING id INTO v_distrib_id;

  -- Un second fabricant, pour vérifier qu'un distributeur affilié ne peut pas
  -- revendiquer la marque d'un concurrent.
  INSERT INTO utilisateurs (nom, telephone, role)
  VALUES ('Marque concurrente du test', '2250700999002', 'fabricant')
  RETURNING id INTO v_scratch;

  INSERT INTO fabricants (utilisateur_id, nom)
  VALUES (v_scratch, 'Marque concurrente du test')
  RETURNING id INTO v_autre_fab;

  -- Le compte de connexion doit exister avant la ligne métier : la clé
  -- étrangère `utilisateurs.auth_user_id` l'exige, en local comme sur
  -- Supabase. C'est la fonction Edge qui s'en charge en production, et c'est
  -- pourquoi elle crée le compte AVANT d'appeler cette fonction.
  INSERT INTO auth.users (id) VALUES (gen_random_uuid()) RETURNING id INTO v_faux_auth;

  -- ── 1. L'agent recenseur inscrit une boutique ────────────────────────────
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'agent_recenseur', 'id_metier', v_agent_id)::TEXT, true);

  v_resultat := creer_compte_metier(
    v_faux_auth, 'Aya Test', '0745999001', 'point_de_vente',
    jsonb_build_object(
      'nom_boutique', 'Boutique du test',
      'type_activite', 'boutique',
      'commune', 'Cocody',
      'latitude', 5.3599,
      'longitude', -3.9862
    ));

  ASSERT v_resultat->>'id_metier' IS NOT NULL, 'Aucune boutique créée';
  ASSERT v_resultat->>'telephone' = '2250745999001',
    format('Numéro mal normalisé : %s', v_resultat->>'telephone');
  RAISE NOTICE '  ok  recensement : la boutique et son compte sont créés d''un bloc';

  -- Le numéro est stocké sous la forme canonique, sans « + ». Les quatre
  -- implémentations de la normalisation (SQL, Dart, fonction Edge, script
  -- d'amorçage) doivent coïncider, sinon un compte se crée sous une adresse et
  -- se connecte sous une autre.
  SELECT count(*) INTO v_nb FROM utilisateurs WHERE telephone = '2250745999001';
  ASSERT v_nb = 1, 'Le numéro normalisé ne se retrouve pas en base';

  -- La boutique est rattachée à l'agent qui l'a recensée, et active tout de suite.
  SELECT count(*) INTO v_nb
    FROM points_de_vente
   WHERE id = (v_resultat->>'id_metier')::UUID
     AND agent_recenseur_id = v_agent_id
     AND statut = 'actif';
  ASSERT v_nb = 1, 'La boutique n''est ni rattachée à son agent ni active';
  RAISE NOTICE '  ok  traçabilité : la boutique porte l''agent qui l''a inscrite';

  -- La suite des tests de revendication porte sur CETTE boutique, pas sur celle
  -- du seed. Celle du seed est déjà desservie par un distributeur, et le test
  -- se heurtait à sa propre règle « une boutique déjà prise ne se reprend pas ».
  -- Partir d'une boutique vierge sépare ce qui est testé de ce qui est acquis.
  v_pdv_id := (v_resultat->>'id_metier')::UUID;

  -- ── 2. Un agent ne se fabrique pas un compte administrateur ──────────────
  BEGIN
    PERFORM creer_compte_metier(pg_temp.compte_auth(), 'Pirate', '0745999002', 'administrateur');
    RAISE EXCEPTION 'Un agent recenseur a pu créer un administrateur';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok  périmètre : l''agent ne peut pas créer d''administrateur';
  END;

  -- ── 3. Ni un livreur, qui relève du distributeur ─────────────────────────
  BEGIN
    PERFORM creer_compte_metier(pg_temp.compte_auth(), 'Livreur', '0745999003', 'livreur');
    RAISE EXCEPTION 'Un agent recenseur a pu créer un livreur';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok  périmètre : l''agent ne peut pas enrôler de livreur';
  END;

  -- ── 4. Un numéro déjà pris est refusé ────────────────────────────────────
  BEGIN
    PERFORM creer_compte_metier(pg_temp.compte_auth(), 'Doublon', '0745999001', 'point_de_vente',
      jsonb_build_object('nom_boutique', 'Doublon', 'type_activite', 'boutique',
                         'commune', 'Cocody', 'latitude', 5.36, 'longitude', -3.98));
    RAISE EXCEPTION 'Un numéro déjà rattaché a été accepté deux fois';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE '  ok  unicité : un numéro ne sert qu''à un seul compte';
  END;

  -- ── 5. Un numéro incomplet est refusé avant toute écriture ───────────────
  BEGIN
    PERFORM creer_compte_metier(pg_temp.compte_auth(), 'Court', '0745', 'point_de_vente',
      jsonb_build_object('nom_boutique', 'Court', 'type_activite', 'boutique',
                         'commune', 'Cocody', 'latitude', 5.36, 'longitude', -3.98));
    RAISE EXCEPTION 'Un numéro incomplet a été accepté';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok  saisie : un numéro incomplet est refusé';
  END;

  -- ── 6. Le distributeur enrôle un livreur, dans SA flotte ─────────────────
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'distributeur', 'id_metier', v_distrib_id)::TEXT, true);

  v_resultat := creer_compte_metier(
    pg_temp.compte_auth(), 'Koffi Test', '0712999001', 'livreur');
  v_livreur_id := (v_resultat->>'id_metier')::UUID;

  SELECT count(*) INTO v_nb
    FROM livreurs WHERE id = v_livreur_id AND distributeur_id = v_distrib_id AND actif;
  ASSERT v_nb = 1, 'Le livreur n''a pas rejoint la flotte de son créateur';
  RAISE NOTICE '  ok  flotte : le livreur créé rejoint la flotte de l''appelant';

  -- La flotte ne se choisit pas : même en passant un autre distributeur dans
  -- les détails, c'est l'identité du jeton qui décide.
  SELECT d.id INTO v_autre_dist FROM distributeurs d WHERE d.id <> v_distrib_id LIMIT 1;
  IF v_autre_dist IS NOT NULL THEN
    v_resultat := creer_compte_metier(
      pg_temp.compte_auth(), 'Détourné', '0712999002', 'livreur',
      jsonb_build_object('distributeur_id', v_autre_dist));
    SELECT distributeur_id INTO v_autre_dist
      FROM livreurs WHERE id = (v_resultat->>'id_metier')::UUID;
    ASSERT v_autre_dist = v_distrib_id,
      'Un distributeur a pu placer un livreur dans la flotte d''un autre';
    RAISE NOTICE '  ok  flotte : la flotte vient du jeton, pas de la requête';
  END IF;

  -- ── 7. Écarter un livreur le rend inaffectable ───────────────────────────
  PERFORM ecarter_livreur(v_livreur_id, false);
  SELECT actif INTO v_actif FROM livreurs WHERE id = v_livreur_id;
  ASSERT NOT v_actif, 'Le livreur écarté est resté actif';

  -- Le contrôle doit vivre dans `affecter_livreur`, pas seulement dans l'écran :
  -- sans cela, écarter quelqu'un ne serait que cosmétique.
  BEGIN
    PERFORM affecter_livreur(
      (SELECT id FROM ruptures WHERE statut = 'signalee' LIMIT 1), v_livreur_id);
    RAISE EXCEPTION 'Un livreur écarté a pu recevoir une course';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok  écartement : un livreur écarté ne reçoit plus de course';
  END;

  PERFORM ecarter_livreur(v_livreur_id, true);
  SELECT actif INTO v_actif FROM livreurs WHERE id = v_livreur_id;
  ASSERT v_actif, 'Le livreur réintégré est resté écarté';
  RAISE NOTICE '  ok  écartement : la réintégration fonctionne';

  -- ── 8. Revendiquer une boutique renseigne le routage ─────────────────────
  --
  -- C'est le point qui débloque le cercle « attribué » : sans
  -- `attributions_reseau.distributeur_id`, toute rupture naît sans destinataire.
  PERFORM renoncer_point_de_vente(v_pdv_id, v_fabricant);
  PERFORM revendiquer_point_de_vente(v_pdv_id, v_fabricant);

  SELECT count(*) INTO v_nb
    FROM attributions_reseau
   WHERE point_de_vente_id = v_pdv_id
     AND fabricant_id = v_fabricant
     AND distributeur_id = v_distrib_id;
  ASSERT v_nb = 1, 'La revendication n''a pas renseigné le distributeur';
  RAISE NOTICE '  ok  réseau : la revendication renseigne le destinataire des ruptures';

  -- ── 9. Une boutique déjà prise ne se vole pas ────────────────────────────
  --
  -- Un second indépendant, créé ici plutôt que cherché dans le seed, qui n'en
  -- contient aucun. Le test se sautait lui-même en silence, ce qui est pire
  -- qu'un échec : il rendait vert sans avoir rien vérifié.
  INSERT INTO utilisateurs (nom, telephone, role)
  VALUES ('Concurrent du test', '2250700999003', 'distributeur')
  RETURNING id INTO v_scratch;

  INSERT INTO distributeurs (utilisateur_id, fabricant_id, nom, telephone)
  VALUES (v_scratch, NULL, 'Concurrent du test', '2250700999003')
  RETURNING id INTO v_autre_dist;

  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'distributeur', 'id_metier', v_autre_dist)::TEXT, true);
  BEGIN
    PERFORM revendiquer_point_de_vente(v_pdv_id, v_fabricant);
    RAISE EXCEPTION 'Une boutique déjà desservie a pu être reprise';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE '  ok  réseau : une boutique déjà desservie ne se reprend pas';
  END;
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'distributeur', 'id_metier', v_distrib_id)::TEXT, true);

  -- ── 10. Un distributeur affilié reste sur sa marque ──────────────────────
  SELECT d.id INTO v_autre_dist FROM distributeurs d WHERE d.fabricant_id IS NOT NULL LIMIT 1;
  SELECT f.id INTO v_autre_fab
    FROM fabricants f
   WHERE f.id <> (SELECT fabricant_id FROM distributeurs WHERE id = v_autre_dist)
   LIMIT 1;

  IF v_autre_dist IS NOT NULL AND v_autre_fab IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims',
      json_build_object('user_role', 'distributeur', 'id_metier', v_autre_dist)::TEXT, true);
    BEGIN
      PERFORM revendiquer_point_de_vente(v_pdv_id, v_autre_fab);
      RAISE EXCEPTION 'Un distributeur affilié a revendiqué la marque d''un concurrent';
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE '  ok  réseau : un distributeur affilié ne porte que sa marque';
    END;
  END IF;

  -- ── 11. Renoncer laisse l'attribution sans destinataire, pas orpheline ───
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'distributeur', 'id_metier', v_distrib_id)::TEXT, true);
  PERFORM renoncer_point_de_vente(v_pdv_id, v_fabricant);

  SELECT count(*) INTO v_nb
    FROM attributions_reseau
   WHERE point_de_vente_id = v_pdv_id AND fabricant_id = v_fabricant
     AND distributeur_id IS NULL;
  ASSERT v_nb = 1,
    'Renoncer a supprimé l''attribution : les ruptures futures se perdraient au lieu de partir au cercle élargi';
  RAISE NOTICE '  ok  réseau : renoncer conserve la couverture du fabricant';

  -- ── 12. Sans jeton, aucune création n'est possible ───────────────────────
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN
    PERFORM creer_compte_metier(pg_temp.compte_auth(), 'Anonyme', '0745999009', 'point_de_vente');
    RAISE EXCEPTION 'Un appel sans identité a créé un compte';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok  identité : sans jeton, rien ne se crée';
  END;

  RAISE NOTICE '';
  RAISE NOTICE 'Gestion du réseau : tous les cas passent.';
END;
$test$;

ROLLBACK;
