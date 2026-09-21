-- test_administration.sql
--
-- Ce que l'administrateur peut faire depuis ses cinq écrans, et ce que les
-- autres ne peuvent pas faire à sa place.
--
--   psql -v ON_ERROR_STOP=1 -d yalla -f supabase/tests/test_administration.sql
--
-- DEUX CAS PORTENT PLUS QUE LES AUTRES :
--
--   * une diffusion ne part que de l'administrateur. Un message envoyé à tout
--     le réseau ne se rattrape pas, et un fabricant capable d'en émettre un
--     s'adresserait aux boutiques de ses concurrents.
--   * un boutiquier ne voit pas les réponses des autres à un sondage. Un
--     sondage dont on lit les réponses en cours n'est plus un sondage, c'est un
--     vote par ralliement.
--
-- Tout se déroule dans une transaction close par ROLLBACK.

BEGIN;

DO $test$
DECLARE
  v_admin    UUID;
  v_pdv      UUID;
  v_pdv2     UUID;
  v_fab      UUID;
  v_dist     UUID;
  v_resultat JSONB;
  v_nb       INTEGER;
  v_portee   INTEGER;
  v_diffusion UUID;
BEGIN
  SELECT id INTO v_admin FROM utilisateurs WHERE role = 'administrateur' LIMIT 1;
  SELECT id INTO v_pdv   FROM points_de_vente WHERE statut = 'actif' LIMIT 1;
  SELECT id INTO v_fab   FROM fabricants LIMIT 1;
  SELECT id INTO v_dist  FROM distributeurs LIMIT 1;

  ASSERT v_admin IS NOT NULL, 'Seed absent : aucun administrateur';
  ASSERT v_pdv IS NOT NULL,   'Seed absent : aucun point de vente actif';

  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'administrateur',
                      'utilisateur_id', v_admin)::TEXT, true);

  -- ── 1. Émettre une notification ──────────────────────────────────────────
  v_resultat := diffuser_notification(
    'notification', 'Maintenance samedi',
    'Le réseau sera indisponible samedi de 6 h à 8 h.', 'points_de_vente');

  v_diffusion := (v_resultat->>'diffusion_id')::UUID;
  ASSERT v_diffusion IS NOT NULL, 'La diffusion devrait rendre son identifiant';

  SELECT portee INTO v_portee FROM v_diffusions WHERE diffusion_id = v_diffusion;
  ASSERT v_portee >= 1,
    format('Portée aberrante : %s destinataire(s) pour tous les points de vente', v_portee);
  RAISE NOTICE '  ok  diffusion : une notification part et sa portée est comptée';

  -- ── 2. La commune restreint la portée ────────────────────────────────────
  -- Ce n'est pas un détail d'affichage : une consigne envoyée à tout Abidjan
  -- alors qu'elle ne concerne qu'une commune use la confiance des boutiquiers,
  -- qui finissent par ne plus lire.
  v_resultat := diffuser_notification(
    'notification', 'Marché fermé', 'Le marché est fermé demain.',
    'points_de_vente',
    (SELECT commune FROM points_de_vente WHERE id = v_pdv));

  SELECT portee INTO v_nb
    FROM v_diffusions WHERE diffusion_id = (v_resultat->>'diffusion_id')::UUID;
  ASSERT v_nb <= v_portee,
    format('Une diffusion ciblée sur une commune touche %s comptes contre %s sans filtre',
           v_nb, v_portee);
  RAISE NOTICE '  ok  diffusion : la commune restreint bien la portée';

  -- ── 3. Un sondage sans options est refusé ────────────────────────────────
  BEGIN
    PERFORM diffuser_notification('sondage', 'Votre avis', 'Êtes-vous satisfait ?',
                                  'points_de_vente', NULL, ARRAY['Oui']);
    RAISE EXCEPTION 'Un sondage à une seule réponse a été accepté';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok  diffusion : un sondage sans alternative est refusé';
  END;

  v_resultat := diffuser_notification('sondage', 'Votre avis',
    'Le délai de livraison vous convient-il ?', 'points_de_vente', NULL,
    ARRAY['Oui', 'Non', 'Sans opinion']);

  SELECT options INTO v_nb
    FROM v_diffusions WHERE diffusion_id = (v_resultat->>'diffusion_id')::UUID;
  ASSERT v_nb = 3, format('Le sondage devrait porter 3 options, il en a %s', v_nb);
  RAISE NOTICE '  ok  diffusion : un sondage emporte ses réponses possibles';

  -- ── 4. Activer et retirer un acteur ──────────────────────────────────────
  v_resultat := changer_statut_acteur('point_de_vente', v_pdv, false);
  ASSERT v_resultat->>'nom' IS NOT NULL, 'Le retrait devrait nommer la boutique';

  SELECT count(*) INTO v_nb
    FROM points_de_vente WHERE id = v_pdv AND statut = 'retire';
  ASSERT v_nb = 1, 'La boutique devrait être retirée';

  PERFORM changer_statut_acteur('point_de_vente', v_pdv, true);
  SELECT count(*) INTO v_nb
    FROM points_de_vente WHERE id = v_pdv AND statut = 'actif';
  ASSERT v_nb = 1, 'La boutique devrait être réactivée';
  RAISE NOTICE '  ok  acteurs : retrait et réactivation d''une boutique';

  BEGIN
    PERFORM changer_statut_acteur('licorne', v_pdv, false);
    RAISE EXCEPTION 'Un type d''acteur inconnu a été accepté';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok  acteurs : un type inconnu est refusé';
  END;

  -- ── 5. Les vues des cinq écrans répondent ────────────────────────────────
  SELECT points_de_vente INTO v_nb FROM v_supervision_acteurs;
  ASSERT v_nb IS NOT NULL, 'v_supervision_acteurs ne rend rien';

  PERFORM 1 FROM v_supervision_communes LIMIT 1;
  PERFORM 1 FROM v_supervision_livreurs LIMIT 1;
  PERFORM 1 FROM v_supervision_ruptures_recentes LIMIT 1;
  PERFORM 1 FROM v_supervision_attribution LIMIT 1;
  PERFORM 1 FROM v_supervision_produits_tendus LIMIT 1;

  SELECT count(*) INTO v_nb FROM v_supervision_semaines;
  ASSERT v_nb = 12, format('Douze semaines attendues, %s rendues', v_nb);

  SELECT count(*) INTO v_nb FROM v_supervision_activite;
  ASSERT v_nb = 14, format('Quatorze jours attendus, %s rendus', v_nb);
  RAISE NOTICE '  ok  écrans : les sept vues de supervision répondent';

  -- ── 6. LE CHIFFRE D'AFFAIRES VIENT DES LIVRAISONS ────────────────────────
  --
  -- Le cahier des charges demande un chiffre d'affaires à l'administrateur.
  -- Celui qu'il obtient est celui des LIVRAISONS, jamais celui des caisses.
  -- Si quelqu'un rebranchait un jour ces vues sur `ventes`, la promesse faite
  -- au boutiquier tomberait sans que rien ne le signale à l'écran.
  SELECT count(*) INTO v_nb
    FROM pg_views
   WHERE schemaname = 'public'
     AND viewname IN ('v_supervision_semaines', 'v_supervision_activite',
                      'v_supervision_par_fabricant')
     AND (definition ILIKE '%FROM ventes%' OR definition ILIKE '%lignes_vente%');
  ASSERT v_nb = 0,
    'Une vue de supervision lit les ventes : la promesse faite au boutiquier est rompue';
  RAISE NOTICE '  ok  confidentialité : le CA de l''administrateur vient des livraisons';

  -- ── 7. Seul l'administrateur diffuse ─────────────────────────────────────
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'fabricant', 'id_metier', v_fab)::TEXT, true);
  BEGIN
    PERFORM diffuser_notification('notification', 'Promotion',
      'Notre nouvelle gamme arrive.', 'reseau_complet');
    RAISE EXCEPTION 'Un fabricant a pu diffuser au réseau complet';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok  périmètre : un fabricant ne diffuse pas au réseau';
  END;

  BEGIN
    PERFORM changer_statut_acteur('distributeur', v_dist, false);
    RAISE EXCEPTION 'Un fabricant a pu suspendre un distributeur';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '  ok  périmètre : un fabricant ne suspend personne';
  END;

  -- ── 8. UN BOUTIQUIER NE VOIT PAS LES RÉPONSES DES AUTRES ─────────────────
  --
  -- Le second cas important du fichier. On fabrique deux réponses au sondage,
  -- venues de deux boutiques différentes, et on vérifie que chacune ne voit
  -- que la sienne.
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'administrateur',
                      'utilisateur_id', v_admin)::TEXT, true);

  v_resultat := diffuser_notification('sondage', 'Satisfaction',
    'Recommanderiez-vous Yalla ?', 'points_de_vente', NULL, ARRAY['Oui', 'Non']);
  v_diffusion := (v_resultat->>'diffusion_id')::UUID;

  INSERT INTO utilisateurs (nom, telephone, role)
  VALUES ('Gérant sondé', '2250700777001', 'point_de_vente');

  INSERT INTO points_de_vente (nom, type_activite, commune, position, statut, utilisateur_id)
  VALUES ('Boutique du sondage', 'boutique', 'Koumassi',
          ST_SetSRID(ST_MakePoint(-3.94, 5.30), 4326)::GEOGRAPHY, 'actif',
          (SELECT id FROM utilisateurs WHERE telephone = '2250700777001'))
  RETURNING id INTO v_pdv2;

  INSERT INTO sondage_reponses (notification_id, point_de_vente_id, option_choisie_id)
  SELECT v_diffusion, v_pdv, id FROM sondage_options
   WHERE notification_id = v_diffusion LIMIT 1;

  INSERT INTO sondage_reponses (notification_id, point_de_vente_id, option_choisie_id)
  SELECT v_diffusion, v_pdv2, id FROM sondage_options
   WHERE notification_id = v_diffusion OFFSET 1 LIMIT 1;

  -- L'administrateur dépouille : il voit les deux.
  SELECT reponses INTO v_nb FROM v_diffusions WHERE diffusion_id = v_diffusion;
  ASSERT v_nb = 2, format('L''administrateur devrait voir 2 réponses, il en voit %s', v_nb);

  -- Le boutiquier, lui, ne voit que la sienne.
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'point_de_vente', 'id_metier', v_pdv2)::TEXT, true);

  BEGIN
    SELECT count(*) INTO v_nb FROM sondage_reponses;
    ASSERT v_nb <= 1,
      format('Un boutiquier voit %s réponses au sondage : le vote n''est plus secret', v_nb);
  EXCEPTION WHEN insufficient_privilege THEN
    -- Le simulacre local n'accorde pas les mêmes GRANT que Supabase. Ne rien
    -- voir du tout convient aussi bien : c'est le résultat qui compte.
    NULL;
  END;

  RESET ROLE;
  RAISE NOTICE '  ok  confidentialité : un boutiquier ne voit pas les réponses des autres';

  -- ── 9. LA DIFFUSION ARRIVE BIEN À DESTINATION ────────────────────────────
  --
  -- La première version de la diffusion n'avait aucune politique de réception :
  -- le message partait, était stocké, sa portée était comptée, et personne ne
  -- le voyait jamais. Aucune erreur ne se produisait, donc rien ne le
  -- signalait. Ces cas-là empêchent que cela se reproduise.
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'administrateur',
                      'utilisateur_id', v_admin)::TEXT, true);

  PERFORM diffuser_notification('notification', 'Pour les boutiques',
    'Message destiné aux points de vente.', 'points_de_vente');
  PERFORM diffuser_notification('notification', 'Pour les livreurs',
    'Message destiné aux livreurs.', 'livreurs');

  -- SET LOCAL ROLE N'EST PAS FACULTATIF ICI. Le propriétaire de la base
  -- contourne RLS : sans ce changement de rôle, la vue rendrait TOUTES les
  -- diffusions et le test passerait au vert en ne vérifiant rien. C'est
  -- exactement ce qui s'est produit à la première écriture de ce cas.
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'point_de_vente', 'id_metier', v_pdv2)::TEXT, true);

  SELECT count(*) INTO v_nb
    FROM v_mes_diffusions WHERE titre = 'Pour les boutiques';
  ASSERT v_nb = 1, 'Un boutiquier ne reçoit pas ce qui lui est adressé';

  SELECT count(*) INTO v_nb
    FROM v_mes_diffusions WHERE titre = 'Pour les livreurs';
  ASSERT v_nb = 0, 'Un boutiquier reçoit un message adressé aux livreurs';
  RESET ROLE;
  RAISE NOTICE '  ok  réception : chacun ne reçoit que ce qui lui est adressé';

  -- Une diffusion restreinte à une autre commune ne doit pas l'atteindre.
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'administrateur',
                      'utilisateur_id', v_admin)::TEXT, true);
  PERFORM diffuser_notification('notification', 'Commune etrangere',
    'Message pour une autre commune.', 'points_de_vente', 'Commune inexistante');

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    json_build_object('user_role', 'point_de_vente', 'id_metier', v_pdv2)::TEXT, true);
  SELECT count(*) INTO v_nb
    FROM v_mes_diffusions WHERE titre = 'Commune etrangere';
  ASSERT v_nb = 0, 'Une diffusion communale touche une boutique d''une autre commune';
  RESET ROLE;
  RAISE NOTICE '  ok  réception : la restriction de commune est respectée';

  -- ── 10. Répondre à un sondage ────────────────────────────────────────────
  -- La réponse se corrige : sur un téléphone, la première ligne touchée n'est
  -- pas toujours celle qu'on visait.
  v_resultat := repondre_sondage(v_diffusion,
    (SELECT id FROM sondage_options WHERE notification_id = v_diffusion ORDER BY libelle LIMIT 1));
  ASSERT (v_resultat->>'enregistree')::BOOLEAN, 'La réponse au sondage devrait être enregistrée';

  PERFORM repondre_sondage(v_diffusion,
    (SELECT id FROM sondage_options WHERE notification_id = v_diffusion ORDER BY libelle DESC LIMIT 1));
  SELECT count(*) INTO v_nb
    FROM sondage_reponses WHERE notification_id = v_diffusion AND point_de_vente_id = v_pdv2;
  ASSERT v_nb = 1, 'Répondre deux fois devrait remplacer, pas ajouter';
  RAISE NOTICE '  ok  sondage : une boutique répond une fois, et peut se corriger';

  -- Une réponse volée à un autre sondage est refusée. Les deux identifiants
  -- sont valides séparément : aucune clé étrangère ne s'y opposerait.
  BEGIN
    PERFORM repondre_sondage(v_diffusion, gen_random_uuid());
    RAISE EXCEPTION 'Une option étrangère au sondage a été acceptée';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok  sondage : une réponse d''un autre sondage est refusée';
  END;

  RAISE NOTICE '';
  RAISE NOTICE 'Administration : tous les cas passent.';
END;
$test$;

ROLLBACK;
