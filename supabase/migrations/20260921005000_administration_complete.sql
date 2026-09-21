-- 20260921005000_administration_complete.sql
--
-- Tout ce que le cahier des charges confie à l'administrateur, et qui manquait.
--
-- La maquette Administrateur décrit cinq écrans : tableau de bord, carte du
-- réseau, acteurs, diffusion, statistiques. Trois n'avaient aucune donnée
-- derrière eux. Cette migration les pose.
--
-- ════════════════════════════════════════════════════════════════════════════
-- ARBITRAGE 1 — LE CHIFFRE D'AFFAIRES DU CAHIER DES CHARGES
-- ════════════════════════════════════════════════════════════════════════════
--
-- La maquette affiche « Chiffre d'affaires du jour : 14,8 M » sur le tableau de
-- bord de l'administrateur, et un « CA par fabricant » dans les statistiques.
-- Pris au pied de la lettre, cela contredit frontalement la promesse inscrite
-- en base : `ventes` et `lignes_vente` n'appartiennent qu'au boutiquier, et les
-- politiques omettent délibérément `est_admin()`.
--
-- Il n'y a pourtant pas de contradiction, parce que DEUX CHIFFRES D'AFFAIRES
-- COEXISTENT dans ce produit, et qu'ils ne mesurent pas la même chose :
--
--   * ce que la boutique encaisse à son comptoir. C'est son commerce à elle.
--     Yalla le voit pour lui rendre sa caisse, et ne le montre à personne.
--     C'est cette promesse qui lui fait accepter la caisse gratuite, donc
--     c'est elle qui fait remonter les ruptures de tout le réseau.
--
--   * ce que les LIVRAISONS Yalla font circuler, c'est-à-dire `livraisons.
--     montant`, l'argent remis au livreur contre le réapprovisionnement. C'est
--     l'activité de la plateforme elle-même, le volume qu'elle génère pour les
--     fabricants et les distributeurs.
--
-- C'est le second que l'administrateur doit voir, et c'est d'ailleurs celui qui
-- a un sens pour lui : il pilote un réseau de distribution, pas des commerces.
-- `v_chiffre_affaires_genere_par_fabricant` le calculait déjà ainsi depuis la
-- migration des distributeurs, sans que l'intention soit écrite noir sur blanc.
-- Elle l'est maintenant.
--
-- ════════════════════════════════════════════════════════════════════════════
-- ARBITRAGE 2 — LA CIBLE « UNE COMMUNE »
-- ════════════════════════════════════════════════════════════════════════════
--
-- La maquette veut pouvoir diffuser au réseau complet, aux points de vente,
-- aux fabricants, aux livreurs, ou à UNE COMMUNE. Les quatre premiers sont des
-- valeurs de `cible_notification` ; la commune n'en est pas une, et ne doit pas
-- le devenir.
--
-- Deux raisons. La première est de conception : une commune n'est pas un rôle,
-- c'est un filtre géographique qui se combine avec un rôle. En faire une
-- cinquième valeur rendrait impossible « les livreurs de Yopougon », qui est
-- pourtant le cas d'usage le plus probable. Une colonne à côté de l'énumération
-- permet les deux.
--
-- La seconde est mécanique : PostgreSQL interdit d'utiliser une valeur
-- d'énumération dans la transaction qui l'ajoute, et `supabase db push`
-- enveloppe chaque migration dans une transaction unique. Un `ALTER TYPE ADD
-- VALUE` suivi d'un usage dans le même fichier échoue au déploiement après être
-- passé en local. Le harnais de tests attrape ce piège, mais autant ne pas le
-- tendre.
--
-- ════════════════════════════════════════════════════════════════════════════
-- ARBITRAGE 3 — LE TAUX DE LECTURE N'EST PAS INVENTÉ
-- ════════════════════════════════════════════════════════════════════════════
--
-- La maquette affiche « Lu : 68 % » sur les diffusions passées. Rien dans le
-- schéma ne trace la lecture d'une notification : il n'existe aucune table
-- d'accusés de réception, et l'application n'en remonte aucun.
--
-- On pourrait fabriquer un pourcentage plausible. Ce serait un chiffre faux
-- affiché comme vrai, sur un écran de pilotage, et il finirait par servir à
-- décider quelque chose. Ce qui est donc rendu ici :
--
--   * la PORTÉE, c'est-à-dire le nombre de destinataires réellement concernés
--     au moment où l'on regarde. Celle-là est exacte.
--   * pour un sondage, le NOMBRE DE RÉPONSES et le taux de réponse, qui sont
--     mesurés pour de bon puisque `sondage_reponses` existe.
--   * pour une notification simple, rien sur la lecture. L'écran écrit « non
--     suivi » plutôt qu'un nombre.
--
-- Le jour où l'application remontera un accusé de lecture, il suffira d'une
-- table et d'une colonne de plus ici.

-- ── 1. Diffusion ────────────────────────────────────────────────────────────

ALTER TABLE notifications ADD COLUMN IF NOT EXISTS commune TEXT;

COMMENT ON COLUMN notifications.commune IS
  'Restriction géographique facultative, qui se combine avec la cible. NULL vaut « partout ».';

-- Les trois tables étaient fermées depuis la migration des périmètres, faute
-- d'écran pour les utiliser. L'administrateur émet, tout le monde lit ce qui le
-- concerne.
CREATE POLICY notifications_admin ON notifications FOR ALL TO authenticated
  USING (est_admin()) WITH CHECK (est_admin());

-- Un fabricant voit ce qu'il a lui-même émis, jamais les diffusions d'un
-- concurrent. La règle est la même que partout ailleurs dans ce schéma.
CREATE POLICY notifications_emetteur ON notifications FOR SELECT TO authenticated
  USING (emetteur_id = auth_utilisateur_id());

CREATE POLICY sondage_options_admin ON sondage_options FOR ALL TO authenticated
  USING (est_admin()) WITH CHECK (est_admin());

-- Les options d'un sondage sont lisibles de ceux qui peuvent y répondre : sans
-- cela, le sondage arrive sans ses réponses possibles.
CREATE POLICY sondage_options_lecture ON sondage_options FOR SELECT TO authenticated
  USING (auth_role() = 'point_de_vente');

CREATE POLICY sondage_reponses_admin ON sondage_reponses FOR SELECT TO authenticated
  USING (est_admin());

-- Le boutiquier écrit sa réponse, et ne lit que la sienne. Il ne voit pas ce
-- qu'ont répondu les autres : un sondage dont on voit les réponses en cours
-- n'est plus un sondage, c'est un vote par ralliement.
CREATE POLICY sondage_reponses_sienne ON sondage_reponses FOR ALL TO authenticated
  USING (auth_role() = 'point_de_vente' AND point_de_vente_id = auth_id_metier())
  WITH CHECK (auth_role() = 'point_de_vente' AND point_de_vente_id = auth_id_metier());

-- Émettre une diffusion. Réservée à l'administrateur.
CREATE OR REPLACE FUNCTION diffuser_notification(
  p_type    TEXT,
  p_titre   TEXT,
  p_message TEXT,
  p_cible   TEXT DEFAULT 'reseau_complet',
  p_commune TEXT DEFAULT NULL,
  p_options TEXT[] DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_id      UUID;
  v_option  TEXT;
  v_portee  INTEGER;
  v_commune TEXT := NULLIF(trim(COALESCE(p_commune, '')), '');
BEGIN
  IF NOT est_admin() THEN
    RAISE EXCEPTION 'Réservé à l''administrateur du réseau'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF length(trim(COALESCE(p_titre, ''))) < 3 THEN
    RAISE EXCEPTION 'Le titre est obligatoire' USING ERRCODE = 'check_violation';
  END IF;
  IF length(trim(COALESCE(p_message, ''))) < 3 THEN
    RAISE EXCEPTION 'Le message est obligatoire' USING ERRCODE = 'check_violation';
  END IF;

  -- Un sondage sans option est un message auquel personne ne peut répondre.
  -- Mieux vaut refuser que d'émettre quelque chose d'inutilisable à tout le
  -- réseau : une diffusion ne se rattrape pas.
  IF p_type = 'sondage'
     AND (p_options IS NULL OR array_length(array_remove(p_options, ''), 1) < 2) THEN
    RAISE EXCEPTION 'Un sondage demande au moins deux réponses possibles'
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO notifications (emetteur_id, type, titre, message, cible, commune)
  VALUES (auth_utilisateur_id(),
          p_type::type_notification,
          trim(p_titre),
          trim(p_message),
          p_cible::cible_notification,
          v_commune)
  RETURNING id INTO v_id;

  IF p_type = 'sondage' THEN
    FOREACH v_option IN ARRAY p_options LOOP
      IF length(trim(COALESCE(v_option, ''))) > 0 THEN
        INSERT INTO sondage_options (notification_id, libelle) VALUES (v_id, trim(v_option));
      END IF;
    END LOOP;
  END IF;

  SELECT portee INTO v_portee FROM v_diffusions WHERE diffusion_id = v_id;

  RETURN jsonb_build_object(
    'diffusion_id', v_id,
    'portee',       COALESCE(v_portee, 0),
    'cible',        p_cible,
    'commune',      v_commune
  );
END;
$fn$;

REVOKE EXECUTE ON FUNCTION diffuser_notification FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION diffuser_notification TO authenticated;

-- La portée se recalcule à chaque lecture plutôt que d'être figée à l'envoi.
-- Les deux se défendent ; celle-ci répond à « combien de comptes cette
-- consigne concerne-t-elle aujourd'hui », qui est la question que se pose
-- l'administrateur quand il relit une diffusion de la semaine dernière.
CREATE VIEW v_diffusions
WITH (security_invoker = on) AS
SELECT
  n.id AS diffusion_id,
  n.type,
  n.titre,
  n.message,
  n.cible,
  n.commune,
  n.date_envoi,
  u.nom AS emetteur,
  (SELECT count(*) FROM sondage_options o WHERE o.notification_id = n.id) AS options,
  (SELECT count(*) FROM sondage_reponses r WHERE r.notification_id = n.id) AS reponses,
  CASE n.cible
    WHEN 'points_de_vente' THEN (
      SELECT count(*) FROM points_de_vente p
       WHERE p.statut = 'actif' AND (n.commune IS NULL OR p.commune = n.commune))
    WHEN 'fabricants' THEN (SELECT count(*) FROM fabricants WHERE statut = 'actif')
    WHEN 'distributeurs' THEN (SELECT count(*) FROM distributeurs WHERE statut = 'actif')
    WHEN 'livreurs' THEN (SELECT count(*) FROM livreurs WHERE actif)
    ELSE (
      SELECT (SELECT count(*) FROM points_de_vente p
               WHERE p.statut = 'actif' AND (n.commune IS NULL OR p.commune = n.commune))
           + (SELECT count(*) FROM fabricants WHERE statut = 'actif')
           + (SELECT count(*) FROM distributeurs WHERE statut = 'actif')
           + (SELECT count(*) FROM livreurs WHERE actif))
  END AS portee
FROM notifications n
LEFT JOIN utilisateurs u ON u.id = n.emetteur_id;

COMMENT ON VIEW v_diffusions IS
  'Diffusions émises, avec leur portée réelle. La lecture n''est pas suivie : aucun accusé n''existe dans le schéma, et un taux inventé serait un chiffre faux sur un écran de pilotage.';

-- ── 2. Les acteurs du réseau ────────────────────────────────────────────────

CREATE VIEW v_supervision_acteurs
WITH (security_invoker = on) AS
SELECT
  (SELECT count(*) FROM points_de_vente WHERE statut = 'actif')                 AS points_de_vente,
  (SELECT count(*) FROM points_de_vente WHERE statut = 'en_attente_activation') AS points_en_attente,
  (SELECT count(*) FROM points_de_vente WHERE statut = 'retire')                AS points_retires,
  (SELECT count(*) FROM fabricants WHERE statut = 'actif')                      AS fabricants,
  (SELECT count(*) FROM fabricants WHERE statut = 'suspendu')                   AS fabricants_suspendus,
  (SELECT count(*) FROM distributeurs WHERE statut = 'actif')                   AS distributeurs,
  (SELECT count(*) FROM distributeurs WHERE statut = 'suspendu')                AS distributeurs_suspendus,
  (SELECT count(*) FROM livreurs WHERE actif)                                   AS livreurs,
  (SELECT count(*) FROM livreurs WHERE NOT actif)                               AS livreurs_ecartes,
  (SELECT count(*) FROM agents_recenseurs)                                      AS agents_recenseurs,
  (SELECT count(*) FROM demandes_acces WHERE statut = 'en_attente')             AS demandes_en_attente;

-- Activer, suspendre ou retirer un acteur du réseau.
--
-- UN SEUL POINT D'ENTRÉE POUR QUATRE TABLES, et c'est délibéré. Les statuts
-- diffèrent d'une table à l'autre (`statut_point_de_vente` a trois valeurs,
-- `statut_fabricant` deux, `livreurs` porte un booléen), mais le geste de
-- l'administrateur est toujours le même : « celui-là ne travaille plus ». La
-- fonction traduit ce geste unique dans la forme de chaque table, plutôt que
-- d'obliger l'écran à connaître trois conventions.
CREATE OR REPLACE FUNCTION changer_statut_acteur(
  p_type  TEXT,
  p_id    UUID,
  p_actif BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_nom TEXT;
BEGIN
  IF NOT est_admin() THEN
    RAISE EXCEPTION 'Réservé à l''administrateur du réseau'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_type = 'point_de_vente' THEN
    UPDATE points_de_vente
       SET statut = CASE WHEN p_actif THEN 'actif' ELSE 'retire' END::statut_point_de_vente
     WHERE id = p_id
    RETURNING nom INTO v_nom;

  ELSIF p_type = 'fabricant' THEN
    UPDATE fabricants
       SET statut = CASE WHEN p_actif THEN 'actif' ELSE 'suspendu' END::statut_fabricant
     WHERE id = p_id
    RETURNING nom INTO v_nom;

  ELSIF p_type = 'distributeur' THEN
    UPDATE distributeurs
       SET statut = CASE WHEN p_actif THEN 'actif' ELSE 'suspendu' END::statut_fabricant
     WHERE id = p_id
    RETURNING nom INTO v_nom;

  ELSIF p_type = 'livreur' THEN
    UPDATE livreurs l
       SET actif = p_actif
      FROM utilisateurs u
     WHERE l.id = p_id AND u.id = l.utilisateur_id
    RETURNING u.nom INTO v_nom;

  ELSE
    RAISE EXCEPTION 'Type d''acteur inconnu : %', p_type USING ERRCODE = 'check_violation';
  END IF;

  IF v_nom IS NULL THEN
    RAISE EXCEPTION 'Acteur introuvable' USING ERRCODE = 'no_data_found';
  END IF;

  RETURN jsonb_build_object('nom', v_nom, 'type', p_type, 'actif', p_actif);
END;
$fn$;

REVOKE EXECUTE ON FUNCTION changer_statut_acteur FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION changer_statut_acteur TO authenticated;

-- L'attribution de réseau, telle que la maquette la présente : par marque,
-- combien de points et sur quel périmètre.
CREATE VIEW v_supervision_attribution
WITH (security_invoker = on) AS
SELECT
  f.id  AS fabricant_id,
  f.nom AS fabricant_nom,
  count(DISTINCT ar.point_de_vente_id) AS points_attribues,
  count(DISTINCT ar.distributeur_id)   AS distributeurs,
  -- Le périmètre se lit, il ne se compte pas : « Cocody, Yopougon » dit à
  -- l'administrateur quelque chose que « 2 communes » ne dit pas.
  string_agg(DISTINCT pdv.commune, ', ' ORDER BY pdv.commune) AS perimetre
FROM fabricants f
LEFT JOIN attributions_reseau ar  ON ar.fabricant_id = f.id
LEFT JOIN points_de_vente pdv     ON pdv.id = ar.point_de_vente_id
GROUP BY f.id, f.nom;

-- ── 3. La carte du réseau ───────────────────────────────────────────────────

-- Les livreurs, avec leur position et leur état réel.
--
-- L'ÉTAT N'EST PAS `en_ligne`. Un téléphone qu'Android a endormi laisse le
-- drapeau à vrai alors que plus aucune position ne remonte, et le distributeur
-- affecte alors une course à quelqu'un qui ne la verra jamais. L'écart entre
-- `en_ligne` et la fraîcheur de la dernière position est donc rendu ici, et
-- c'est lui qui compte.
CREATE VIEW v_supervision_livreurs
WITH (security_invoker = on) AS
SELECT
  l.id AS livreur_id,
  u.nom,
  u.telephone,
  l.actif,
  l.en_ligne,
  l.position_maj_le,
  d.nom AS distributeur,
  f.nom AS marque,
  ST_Y(l.position::GEOMETRY) AS latitude,
  ST_X(l.position::GEOMETRY) AS longitude,
  EXTRACT(EPOCH FROM (now() - l.position_maj_le))::INTEGER AS position_age_secondes,
  (SELECT count(*) FROM livraisons lv
    WHERE lv.livreur_id = l.id AND lv.statut = 'en_cours') AS courses_en_cours,
  (SELECT count(*) FROM livraisons lv
    WHERE lv.livreur_id = l.id AND lv.statut = 'terminee') AS livraisons_terminees,
  -- La commune n'est pas stockée sur un livreur : on la déduit de la boutique
  -- la plus proche de sa dernière position. C'est une approximation, et elle
  -- est bonne, parce qu'un livreur en course est par construction près d'une
  -- boutique du réseau.
  (SELECT p.commune FROM points_de_vente p
    WHERE p.position IS NOT NULL AND l.position IS NOT NULL
    ORDER BY p.position <-> l.position LIMIT 1) AS commune_approchee
FROM livreurs l
JOIN utilisateurs u       ON u.id = l.utilisateur_id
LEFT JOIN distributeurs d ON d.id = l.distributeur_id
LEFT JOIN fabricants f    ON f.id = d.fabricant_id;

CREATE VIEW v_supervision_communes
WITH (security_invoker = on) AS
SELECT
  pdv.commune,
  count(*) FILTER (WHERE pdv.statut = 'actif')  AS points,
  count(*) FILTER (WHERE pdv.statut <> 'actif') AS points_inactifs,
  count(*) FILTER (WHERE pdv.statut = 'actif' AND NOT EXISTS (
    SELECT 1 FROM attributions_reseau ar
     WHERE ar.point_de_vente_id = pdv.id AND ar.distributeur_id IS NOT NULL
  )) AS points_sans_distributeur,
  (SELECT count(*) FROM ruptures r
     JOIN points_de_vente p2 ON p2.id = r.point_de_vente_id
    WHERE p2.commune = pdv.commune
      AND r.statut = 'signalee' AND r.confirmee_le IS NOT NULL) AS ruptures,
  (SELECT count(DISTINCT s.point_de_vente_id) FROM stocks s
     JOIN points_de_vente p3 ON p3.id = s.point_de_vente_id
    WHERE p3.commune = pdv.commune) AS points_avec_stock
FROM points_de_vente pdv
GROUP BY pdv.commune;

-- ── 4. Les ruptures récentes ────────────────────────────────────────────────
--
-- Le délai est celui de l'attente RÉELLE : il court depuis la confirmation par
-- le boutiquier, pas depuis la naissance du signalement. Une rupture détectée
-- automatiquement mais jamais confirmée n'attend personne, et la compter
-- ferait croire à un retard qui n'existe pas.

CREATE VIEW v_supervision_ruptures_recentes
WITH (security_invoker = on) AS
SELECT
  r.id AS rupture_id,
  r.statut,
  pdv.nom     AS point_de_vente,
  pdv.commune,
  p.nom       AS produit,
  p.image_url,
  f.nom       AS marque,
  d.nom       AS distributeur,
  r.quantite_demandee,
  r.signalement_automatique,
  r.date_signalement,
  r.confirmee_le,
  EXTRACT(EPOCH FROM (now() - COALESCE(r.confirmee_le, r.date_signalement)))::INTEGER
    AS attente_secondes
FROM ruptures r
JOIN points_de_vente pdv  ON pdv.id = r.point_de_vente_id
JOIN produits p           ON p.id = r.produit_id
JOIN fabricants f         ON f.id = p.fabricant_id
LEFT JOIN distributeurs d ON d.id = r.distributeur_id
WHERE r.statut IN ('signalee', 'prise_en_charge');

-- ── 5. Les statistiques ─────────────────────────────────────────────────────

-- Douze semaines d'activité, en semaines et non en jours.
--
-- POURQUOI DES SEMAINES. Quatre-vingt-quatre points quotidiens sur une largeur
-- de carte tracent du bruit, pas une tendance. Le regroupement hebdomadaire
-- est celui de la maquette, et c'est aussi la maille à laquelle un réseau de
-- distribution se pilote : personne ne décide quoi que ce soit sur la base
-- d'un mardi.
CREATE VIEW v_supervision_semaines
WITH (security_invoker = on) AS
SELECT
  s.semaine::DATE AS semaine,
  (SELECT count(*) FROM livraisons l
    WHERE l.statut = 'terminee'
      AND l.date_fin >= s.semaine AND l.date_fin < s.semaine + INTERVAL '7 days') AS livraisons,
  (SELECT COALESCE(sum(l.montant), 0) FROM livraisons l
    WHERE l.statut = 'terminee'
      AND l.date_fin >= s.semaine AND l.date_fin < s.semaine + INTERVAL '7 days') AS montant,
  (SELECT count(*) FROM ruptures r
    WHERE r.date_signalement >= s.semaine
      AND r.date_signalement < s.semaine + INTERVAL '7 days') AS ruptures
FROM generate_series(
       date_trunc('week', now()) - INTERVAL '11 weeks',
       date_trunc('week', now()),
       INTERVAL '1 week'
     ) AS s(semaine);

-- Le classement par marque, avec son évolution.
--
-- L'ÉVOLUTION COMPARE LES TRENTE DERNIERS JOURS AUX TRENTE PRÉCÉDENTS. Une
-- comparaison à la veille, comme sur la maquette, n'a pas de sens sur un
-- réseau de proximité où un jour férié suffit à tout renverser. Trente jours
-- contre trente absorbent la semaine et les jours de marché.
CREATE VIEW v_supervision_par_fabricant
WITH (security_invoker = on) AS
SELECT
  f.id  AS fabricant_id,
  f.nom AS fabricant_nom,
  ca.chiffre_affaires,
  ca.nombre_livraisons,
  ts.taux_de_service_pct,
  (SELECT COALESCE(sum(l.montant), 0)
     FROM livraisons l
     JOIN ruptures r ON r.id = l.rupture_id
     JOIN produits p ON p.id = r.produit_id
    WHERE p.fabricant_id = f.id AND l.statut = 'terminee'
      AND l.date_fin >= now() - INTERVAL '30 days') AS montant_30j,
  (SELECT COALESCE(sum(l.montant), 0)
     FROM livraisons l
     JOIN ruptures r ON r.id = l.rupture_id
     JOIN produits p ON p.id = r.produit_id
    WHERE p.fabricant_id = f.id AND l.statut = 'terminee'
      AND l.date_fin >= now() - INTERVAL '60 days'
      AND l.date_fin <  now() - INTERVAL '30 days') AS montant_30j_precedents
FROM fabricants f
LEFT JOIN v_chiffre_affaires_genere_par_fabricant ca ON ca.fabricant_id = f.id
LEFT JOIN v_taux_de_service_par_fabricant ts         ON ts.fabricant_id = f.id;

-- Les produits qui manquent le plus souvent.
--
-- C'EST LA VUE LA PLUS VENDABLE DU PRODUIT, et elle n'avait aucun écran. Un
-- fabricant paie pour savoir que sa référence phare est en rupture dans
-- quarante boutiques : c'est une information qu'aucun de ses relevés de ventes
-- ne lui donnera jamais, puisqu'une vente qui n'a pas lieu ne laisse aucune
-- trace chez lui.
CREATE VIEW v_supervision_produits_tendus
WITH (security_invoker = on) AS
SELECT
  p.id  AS produit_id,
  p.nom AS produit,
  p.reference,
  p.image_url,
  f.nom AS marque,
  count(*) AS signalements,
  count(*) FILTER (WHERE r.statut = 'signalee')    AS en_cours,
  count(*) FILTER (WHERE r.statut = 'non_servie')  AS non_servies,
  count(*) FILTER (WHERE r.statut = 'resolue')     AS servies,
  count(DISTINCT r.point_de_vente_id)              AS boutiques_touchees,
  max(r.date_signalement)                          AS dernier_signalement
FROM ruptures r
JOIN produits p   ON p.id = r.produit_id
JOIN fabricants f ON f.id = p.fabricant_id
GROUP BY p.id, p.nom, p.reference, p.image_url, f.nom;

-- ── 6. Le montant sur la courbe quotidienne ─────────────────────────────────
--
-- La vue de rythme existait déjà ; il lui manquait l'argent. `CREATE OR
-- REPLACE` n'autorise qu'un ajout en fin de liste, et `security_invoker` doit
-- être redéclaré, faute de quoi la vue se mettrait à contourner RLS.

CREATE OR REPLACE VIEW v_supervision_activite
WITH (security_invoker = on) AS
SELECT
  j.jour::DATE AS jour,
  (SELECT count(*) FROM ruptures r
    WHERE r.date_signalement >= j.jour
      AND r.date_signalement <  j.jour + INTERVAL '1 day') AS signalees,
  (SELECT count(*) FROM ruptures r
    WHERE r.statut = 'resolue'
      AND r.date_resolution >= j.jour
      AND r.date_resolution <  j.jour + INTERVAL '1 day') AS resolues,
  (SELECT count(*) FROM livraisons l
    WHERE l.date_debut >= j.jour
      AND l.date_debut <  j.jour + INTERVAL '1 day') AS livraisons,
  (SELECT COALESCE(sum(l.montant), 0) FROM livraisons l
    WHERE l.statut = 'terminee'
      AND l.date_fin >= j.jour
      AND l.date_fin <  j.jour + INTERVAL '1 day') AS montant
FROM generate_series(
       date_trunc('day', now()) - INTERVAL '13 days',
       date_trunc('day', now()),
       INTERVAL '1 day'
     ) AS j(jour);
