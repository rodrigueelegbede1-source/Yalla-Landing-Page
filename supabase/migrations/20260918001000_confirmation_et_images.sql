-- 20260918001000_confirmation_et_images.sql
--
-- Deux changements demandés après avoir vu les écrans :
--
--   1. Une rupture détectée par la caisse doit être CONFIRMÉE par le boutiquier
--      avant de partir au distributeur.
--   2. Les produits portent une image, et elle doit remonter partout où l'on
--      choisit ou identifie un produit.
--
-- ── CE QUE LA CONFIRMATION CHANGE AU PRODUIT ────────────────────────────────
--
-- Elle inverse le mécanisme central, et il faut le dire clairement : jusqu'ici
-- le boutiquier n'avait rien à faire, et c'était l'argument qui rendait le
-- signalement automatique possible. Désormais une rupture détectée n'existe
-- pour personne tant qu'il n'a pas répondu.
--
-- Le risque assumé est l'oubli : une rupture non confirmée n'est jamais servie,
-- et le boutiquier ne s'en aperçoit qu'en constatant que rien n'arrive. Trois
-- choses le limitent, aucune ne le supprime :
--
--   * la demande apparaît immédiatement après l'encaissement, au moment où il
--     tient encore son téléphone et où le coût d'un geste est presque nul ;
--   * `v_ruptures_a_confirmer` alimente un compteur visible en permanence sur
--     l'écran de la boutique ;
--   * une demande sans réponse est purgée au bout de `delai_peremption()`,
--     comme une rupture ouverte, plutôt que de s'accumuler indéfiniment.
--
-- ── CE QUI N'EST PAS SOUMIS À CONFIRMATION ──────────────────────────────────
--
-- Un signalement fait à la main par le boutiquier est confirmé d'office : il
-- vient de lui, lui redemander son accord n'aurait aucun sens.
--
-- ── LE DÉLAI D'ESCALADE PART DE LA CONFIRMATION, PAS DU SIGNALEMENT ─────────
--
-- Sans quoi une rupture confirmée trois heures après sa détection arriverait
-- déjà périmée chez le distributeur, punissant celui-ci pour l'attente du
-- boutiquier. Le compte à rebours des deux heures démarre donc quand la course
-- devient visible, ce qui est le seul instant où quelqu'un peut agir dessus.

-- ── 1. La confirmation ──────────────────────────────────────────────────────

ALTER TABLE ruptures ADD COLUMN IF NOT EXISTS confirmee_le TIMESTAMPTZ;

COMMENT ON COLUMN ruptures.confirmee_le IS
  'Instant où le point de vente a confirmé la rupture. Nul = invisible du distributeur. Renseigné d''office pour un signalement manuel.';

-- Tout ce qui existe déjà est considéré comme confirmé : ces ruptures ont été
-- créées sous l'ancienne règle et circulent depuis. Les rendre soudainement
-- invisibles ferait disparaître des courses en cours.
UPDATE ruptures SET confirmee_le = date_signalement WHERE confirmee_le IS NULL;

CREATE INDEX IF NOT EXISTS idx_ruptures_a_confirmer
  ON ruptures(point_de_vente_id)
  WHERE confirmee_le IS NULL AND statut = 'signalee';

-- Le trigger de caisse crée la rupture sans la confirmer. Le signalement
-- manuel, lui, passe par `signaler_rupture()` plus bas, qui la confirme.
CREATE OR REPLACE FUNCTION marquer_confirmation_rupture()
RETURNS TRIGGER
LANGUAGE plpgsql AS $fn$
BEGIN
  -- Une rupture née d'une vente attend l'accord du boutiquier. Une rupture
  -- qu'il a lui-même signalée est confirmée par le fait même de l'avoir créée.
  IF NEW.confirmee_le IS NULL AND NOT NEW.signalement_automatique THEN
    NEW.confirmee_le := now();
  END IF;
  RETURN NEW;
END;
$fn$;

-- BEFORE INSERT, et après `trg_ruptures_resout_destinataire` dans l'ordre
-- alphabétique des noms, ce qui est l'ordre d'exécution des triggers de même
-- moment en PostgreSQL. Les deux sont indépendants, l'ordre n'a pas d'effet.
DROP TRIGGER IF EXISTS trg_ruptures_confirmation ON ruptures;
CREATE TRIGGER trg_ruptures_confirmation
  BEFORE INSERT ON ruptures
  FOR EACH ROW EXECUTE FUNCTION marquer_confirmation_rupture();

-- ── 2. Le distributeur ne voit que ce qui est confirmé ──────────────────────

-- L'option est REPOSÉE explicitement : `CREATE OR REPLACE VIEW` ne conserve
-- pas les options de la vue remplacée, il les ramène à leur défaut. Une vue qui
-- perd `security_invoker` s'exécute avec les droits de son propriétaire et
-- contourne silencieusement toutes les politiques. Le contrôle du harnais l'a
-- attrapé avant le déploiement.
CREATE OR REPLACE VIEW v_acces_rupture_distributeur
WITH (security_invoker = on) AS
SELECT r.id AS rupture_id, r.distributeur_id, 'attribue'::TEXT AS cercle
FROM ruptures r
WHERE r.statut = 'signalee'
  AND r.confirmee_le IS NOT NULL
  AND r.distributeur_id IS NOT NULL
UNION
SELECT r.id, ar.distributeur_id, 'elargi'::TEXT
FROM ruptures r
JOIN produits p ON p.id = r.produit_id
JOIN points_de_vente pdv ON pdv.id = r.point_de_vente_id
JOIN attributions_reseau ar ON ar.fabricant_id = p.fabricant_id
JOIN points_de_vente autre ON autre.id = ar.point_de_vente_id
                          AND autre.commune = pdv.commune
WHERE r.statut = 'signalee'
  AND r.confirmee_le IS NOT NULL
  AND r.escaladee_le IS NOT NULL
  AND ar.distributeur_id IS NOT NULL
  AND ar.distributeur_id IS DISTINCT FROM r.distributeur_id;

-- La fonction d'aide RLS suit la même règle, sinon un distributeur pourrait
-- encore lire par un autre chemin une rupture qu'il ne doit pas voir.
CREATE OR REPLACE FUNCTION distributeur_voit_rupture(p_rupture_id UUID, p_distributeur_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM ruptures r
     WHERE r.id = p_rupture_id
       AND r.confirmee_le IS NOT NULL
       AND r.distributeur_id = p_distributeur_id
    UNION ALL
    SELECT 1 FROM ruptures r
      JOIN produits p ON p.id = r.produit_id
      JOIN points_de_vente pdv ON pdv.id = r.point_de_vente_id
      JOIN attributions_reseau ar ON ar.fabricant_id = p.fabricant_id
      JOIN points_de_vente autre ON autre.id = ar.point_de_vente_id
                                AND autre.commune = pdv.commune
     WHERE r.id = p_rupture_id
       AND r.confirmee_le IS NOT NULL
       AND r.escaladee_le IS NOT NULL
       AND ar.distributeur_id = p_distributeur_id
  );
$fn$;

-- ── 3. L'escalade compte à partir de la confirmation ────────────────────────

CREATE OR REPLACE FUNCTION escalader_ruptures_en_attente()
RETURNS TABLE (rupture_id UUID, action TEXT) AS $fn$
BEGIN
  RETURN QUERY
  UPDATE ruptures
  SET escaladee_le = now()
  WHERE statut = 'signalee'
    AND confirmee_le IS NOT NULL
    AND escaladee_le IS NULL
    AND confirmee_le < now() - delai_escalade()
  RETURNING id, 'escaladee'::TEXT;

  RETURN QUERY
  UPDATE ruptures
  SET statut = 'non_servie',
      date_resolution = now()
  WHERE statut = 'signalee'
    AND confirmee_le IS NOT NULL
    AND escaladee_le IS NOT NULL
    AND confirmee_le < now() - delai_peremption()
  RETURNING id, 'perimee'::TEXT;

  -- Les demandes de confirmation sans réponse finissent par tomber, sinon
  -- elles s'accumulent sur l'écran du boutiquier jusqu'à le rendre illisible.
  -- Elles ne comptent PAS comme non servies : personne n'a jamais été sollicité,
  -- ce n'est pas un échec du réseau et le taux de service n'a pas à en pâtir.
  RETURN QUERY
  DELETE FROM ruptures
  WHERE statut = 'signalee'
    AND confirmee_le IS NULL
    AND date_signalement < now() - delai_peremption()
  RETURNING id, 'confirmation_abandonnee'::TEXT;

  RETURN;
END;
$fn$ LANGUAGE plpgsql;

-- ── 4. Ce que le boutiquier doit confirmer ──────────────────────────────────

CREATE VIEW v_ruptures_a_confirmer
WITH (security_invoker = on) AS
SELECT
  r.id AS rupture_id,
  r.point_de_vente_id,
  r.produit_id,
  p.nom       AS produit_nom,
  p.reference,
  p.image_url,
  f.id        AS fabricant_id,
  f.nom       AS fabricant_nom,
  c.nom       AS categorie_nom,
  r.quantite_demandee,
  r.date_signalement,
  EXTRACT(EPOCH FROM (now() - r.date_signalement))::INTEGER AS anciennete_secondes
FROM ruptures r
JOIN produits p            ON p.id = r.produit_id
JOIN fabricants f          ON f.id = p.fabricant_id
LEFT JOIN categories_produit c ON c.id = p.categorie_id
WHERE r.confirmee_le IS NULL
  AND r.statut = 'signalee';

COMMENT ON VIEW v_ruptures_a_confirmer IS
  'Ruptures détectées par la caisse et en attente de l''accord du point de vente. Invisibles du distributeur tant qu''elles sont là.';

CREATE OR REPLACE FUNCTION confirmer_rupture(
  p_rupture_id UUID,
  p_quantite   INTEGER DEFAULT NULL
)
RETURNS ruptures
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_rupture ruptures;
BEGIN
  IF auth_role() <> 'point_de_vente' THEN
    RAISE EXCEPTION 'Seul le point de vente confirme ses ruptures'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- La quantité est révisable au moment de confirmer : la caisse propose ce
  -- qu'elle a vu sortir, le boutiquier sait ce qu'il veut vraiment recevoir.
  UPDATE ruptures
     SET confirmee_le = now(),
         quantite_demandee = COALESCE(p_quantite, quantite_demandee),
         -- Le compte à rebours part d'ici, pas de la détection.
         date_signalement = now()
   WHERE id = p_rupture_id
     AND point_de_vente_id = auth_id_metier()
     AND confirmee_le IS NULL
     AND statut = 'signalee'
  RETURNING * INTO v_rupture;

  IF v_rupture.id IS NULL THEN
    RAISE EXCEPTION 'Cette rupture n''existe plus, ou a déjà été confirmée'
      USING ERRCODE = 'no_data_found';
  END IF;

  RETURN v_rupture;
END;
$fn$;

CREATE OR REPLACE FUNCTION rejeter_rupture(p_rupture_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_touchees INTEGER;
BEGIN
  IF auth_role() <> 'point_de_vente' THEN
    RAISE EXCEPTION 'Seul le point de vente rejette ses ruptures'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Supprimée et non close en « non_servie » : elle n'a jamais été proposée à
  -- personne. La compter comme un échec fausserait le taux de service, qui est
  -- l'indicateur vendu au fabricant.
  DELETE FROM ruptures
   WHERE id = p_rupture_id
     AND point_de_vente_id = auth_id_metier()
     AND confirmee_le IS NULL
     AND statut = 'signalee';

  GET DIAGNOSTICS v_touchees = ROW_COUNT;
  RETURN v_touchees > 0;
END;
$fn$;

-- ── 5. Signaler depuis le catalogue, sans passer par la caisse ──────────────
--
-- Tous les boutiquiers n'utiliseront pas la caisse. Celui qui tient ses comptes
-- sur un cahier doit pouvoir demander un produit quand même, en le choisissant
-- dans le catalogue du fabricant. C'est aussi le seul chemin pour demander un
-- produit qu'on ne suit pas en stock, voire qu'on n'a jamais vendu.
--
-- Contrairement au signalement par la caisse, celui-ci est confirmé d'office.

CREATE OR REPLACE FUNCTION signaler_rupture(
  p_produit_id UUID,
  p_quantite   INTEGER DEFAULT NULL
)
RETURNS ruptures
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_pdv     UUID := auth_id_metier();
  v_rupture ruptures;
BEGIN
  IF auth_role() <> 'point_de_vente' THEN
    RAISE EXCEPTION 'Seul le point de vente signale une rupture'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM produits WHERE id = p_produit_id AND disponible) THEN
    RAISE EXCEPTION 'Ce produit n''est plus au catalogue'
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Deux demandes pour le même produit n'ont pas de sens : on rend celle qui
  -- existe déjà, en la confirmant au passage si elle venait de la caisse.
  SELECT * INTO v_rupture
    FROM ruptures
   WHERE point_de_vente_id = v_pdv
     AND produit_id = p_produit_id
     AND statut IN ('signalee', 'prise_en_charge')
   LIMIT 1;

  IF v_rupture.id IS NOT NULL THEN
    IF v_rupture.confirmee_le IS NULL THEN
      UPDATE ruptures
         SET confirmee_le = now(),
             date_signalement = now(),
             quantite_demandee = COALESCE(p_quantite, quantite_demandee)
       WHERE id = v_rupture.id
      RETURNING * INTO v_rupture;
    END IF;
    RETURN v_rupture;
  END IF;

  INSERT INTO ruptures (point_de_vente_id, produit_id, statut,
                        signalement_automatique, quantite_demandee, confirmee_le)
  VALUES (v_pdv, p_produit_id, 'signalee', false, p_quantite, now())
  RETURNING * INTO v_rupture;

  RETURN v_rupture;
END;
$fn$;

-- Le catalogue tel que le boutiquier le parcourt : tous les produits des
-- fabricants qui desservent sa boutique, avec leur image, et l'indication de ce
-- qu'il suit déjà en stock ou a déjà demandé.
CREATE VIEW v_catalogue_point_de_vente
WITH (security_invoker = on) AS
SELECT
  ar.point_de_vente_id,
  p.id            AS produit_id,
  p.nom           AS produit_nom,
  p.reference,
  p.image_url,
  f.id            AS fabricant_id,
  f.nom           AS fabricant_nom,
  c.nom           AS categorie_nom,
  s.quantite      AS quantite_en_stock,
  EXISTS (
    SELECT 1 FROM ruptures r
     WHERE r.produit_id = p.id
       AND r.point_de_vente_id = ar.point_de_vente_id
       AND r.statut IN ('signalee', 'prise_en_charge')
  ) AS deja_demande
FROM attributions_reseau ar
JOIN produits p   ON p.fabricant_id = ar.fabricant_id AND p.disponible
JOIN fabricants f ON f.id = ar.fabricant_id
LEFT JOIN categories_produit c ON c.id = p.categorie_id
LEFT JOIN stocks s ON s.produit_id = p.id AND s.point_de_vente_id = ar.point_de_vente_id;

COMMENT ON VIEW v_catalogue_point_de_vente IS
  'Le catalogue des fabricants qui desservent cette boutique. Permet de demander un produit sans passer par la caisse, et sans le suivre en stock.';

-- Le boutiquier doit pouvoir lire le catalogue de ses fabricants. `produits`
-- est déjà lisible de tous les comptes authentifiés, mais `attributions_reseau`
-- ne l'était que pour le distributeur et l'administrateur : sans cette
-- politique, la vue ne rendait rien.
CREATE POLICY attributions_du_point_de_vente ON attributions_reseau FOR SELECT TO authenticated
  USING (
    auth_role() = 'point_de_vente'
    AND point_de_vente_id = auth_id_metier()
  );

-- ── 6. L'image remonte partout où l'on identifie un produit ─────────────────
--
-- `produits.image_url` existait depuis la première migration et n'était exposée
-- nulle part. Une image sert à choisir vite, et à lever un doute : « le riz
-- Maman 900 g » ne dit pas grand-chose, le sachet sur l'étagère, si.

CREATE OR REPLACE VIEW v_ruptures_ouvertes
WITH (security_invoker = on) AS
SELECT
  r.id AS rupture_id,
  r.point_de_vente_id,
  pdv.nom AS point_de_vente_nom,
  pdv.commune,
  pdv.position,
  r.produit_id,
  p.nom AS produit_nom,
  p.fabricant_id,
  r.statut,
  r.signalement_automatique,
  r.date_signalement,
  r.distributeur_id,
  r.escaladee_le,
  r.livreur_id,
  r.date_prise_en_charge,
  -- Ajoutées en fin de liste : `CREATE OR REPLACE VIEW` n'autorise rien d'autre.
  p.image_url,
  p.reference,
  pdv.adresse,
  pdv.telephone AS point_de_vente_telephone,
  r.confirmee_le
FROM ruptures r
JOIN points_de_vente pdv ON pdv.id = r.point_de_vente_id
JOIN produits p ON p.id = r.produit_id
WHERE r.statut IN ('signalee', 'prise_en_charge');

DROP VIEW IF EXISTS v_carnet_distributeur;
CREATE VIEW v_carnet_distributeur
WITH (security_invoker = on) AS
SELECT
  acc.distributeur_id,
  acc.cercle,
  ro.rupture_id,
  ro.point_de_vente_id,
  ro.point_de_vente_nom,
  ro.commune,
  ro.adresse,
  ro.point_de_vente_telephone,
  ro.produit_id,
  ro.produit_nom,
  ro.reference,
  ro.image_url,
  ro.fabricant_id,
  f.nom            AS fabricant_nom,
  c.nom            AS categorie_nom,
  r.quantite_demandee,
  ro.statut,
  ro.signalement_automatique,
  ro.date_signalement,
  ro.confirmee_le,
  ro.escaladee_le,
  ro.livreur_id,
  -- Le compte à rebours part de la confirmation : c'est l'instant où la course
  -- est devenue visible, donc le seul à partir duquel quelqu'un pouvait agir.
  GREATEST(
    EXTRACT(EPOCH FROM (ro.confirmee_le + delai_escalade() - now()))::INTEGER,
    0
  ) AS secondes_avant_escalade,
  EXTRACT(EPOCH FROM (now() - ro.confirmee_le))::INTEGER AS anciennete_secondes
FROM v_acces_rupture_distributeur acc
JOIN v_ruptures_ouvertes ro ON ro.rupture_id = acc.rupture_id
JOIN ruptures r             ON r.id = ro.rupture_id
JOIN fabricants f           ON f.id = ro.fabricant_id
LEFT JOIN produits p        ON p.id = ro.produit_id
LEFT JOIN categories_produit c ON c.id = p.categorie_id;

DROP FUNCTION IF EXISTS courses_a_proximite(INTEGER);
CREATE FUNCTION courses_a_proximite(p_limite INTEGER DEFAULT 20)
RETURNS TABLE (
  rupture_id         UUID,
  point_de_vente_nom TEXT,
  commune            TEXT,
  produit_nom        TEXT,
  quantite_demandee  INTEGER,
  cercle             TEXT,
  date_signalement   TIMESTAMPTZ,
  distance_metres    DOUBLE PRECISION,
  image_url          TEXT,
  reference          TEXT,
  fabricant_nom      TEXT,
  adresse            TEXT
)
LANGUAGE sql STABLE AS $fn$
  SELECT ro.rupture_id,
         ro.point_de_vente_nom,
         ro.commune,
         ro.produit_nom,
         r.quantite_demandee,
         acc.cercle,
         ro.date_signalement,
         ST_Distance(ro.position, l.position) AS distance_metres,
         ro.image_url,
         ro.reference,
         f.nom AS fabricant_nom,
         ro.adresse
    FROM v_ruptures_ouvertes ro
    JOIN v_acces_rupture_distributeur acc ON acc.rupture_id = ro.rupture_id
    JOIN ruptures r   ON r.id = ro.rupture_id
    JOIN fabricants f ON f.id = ro.fabricant_id
    JOIN livreurs l   ON l.id = auth_id_metier()
                     AND l.distributeur_id = acc.distributeur_id
   WHERE ro.statut = 'signalee'
   ORDER BY ro.position <-> l.position
   LIMIT p_limite;
$fn$;

COMMENT ON FUNCTION courses_a_proximite IS
  'Ruptures que le livreur connecté peut prendre, triées par distance réelle (PostGIS), avec l''image du produit.';

REVOKE EXECUTE ON FUNCTION courses_a_proximite FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION courses_a_proximite TO authenticated;

DROP VIEW IF EXISTS v_stock_point_de_vente;
CREATE VIEW v_stock_point_de_vente
WITH (security_invoker = on) AS
SELECT
  s.point_de_vente_id,
  s.produit_id,
  COALESCE(p.nom, s.produit_libre_nom) AS produit_nom,
  p.reference,
  p.image_url,
  f.nom AS fabricant_nom,
  c.nom AS categorie_nom,
  s.quantite,
  s.date_maj,
  EXISTS (
    SELECT 1 FROM ruptures r
     WHERE r.produit_id = s.produit_id
       AND r.point_de_vente_id = s.point_de_vente_id
       AND r.statut IN ('signalee', 'prise_en_charge')
  ) AS rupture_ouverte
FROM stocks s
LEFT JOIN produits p ON p.id = s.produit_id
LEFT JOIN fabricants f ON f.id = p.fabricant_id
LEFT JOIN categories_produit c ON c.id = p.categorie_id;

DROP VIEW IF EXISTS v_mes_courses;
CREATE VIEW v_mes_courses
WITH (security_invoker = on) AS
SELECT
  l.id                AS livraison_id,
  l.rupture_id,
  l.statut            AS statut_livraison,
  l.date_debut,
  l.montant,
  pdv.id              AS point_de_vente_id,
  pdv.nom             AS point_de_vente_nom,
  pdv.adresse,
  pdv.commune,
  pdv.telephone       AS point_de_vente_telephone,
  pdv.gerant_nom,
  ST_Y(pdv.position::GEOMETRY) AS latitude,
  ST_X(pdv.position::GEOMETRY) AS longitude,
  p.nom               AS produit_nom,
  p.reference         AS produit_reference,
  p.image_url,
  f.nom               AS fabricant_nom,
  c.nom               AS categorie_nom,
  r.quantite_demandee,
  r.statut            AS statut_rupture
FROM livraisons l
JOIN ruptures r          ON r.id = l.rupture_id
JOIN points_de_vente pdv ON pdv.id = l.point_de_vente_id
JOIN produits p          ON p.id = r.produit_id
JOIN fabricants f        ON f.id = p.fabricant_id
LEFT JOIN categories_produit c ON c.id = p.categorie_id;

-- ── 7. Droits ───────────────────────────────────────────────────────────────

REVOKE EXECUTE ON FUNCTION confirmer_rupture, rejeter_rupture, signaler_rupture
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION confirmer_rupture, rejeter_rupture, signaler_rupture
  TO authenticated;
