-- 011_distributeurs_et_escalade.sql
--
-- Introduit le distributeur, sixième acteur de la chaîne, et le routage complet
-- d'une rupture : à qui elle part, qui l'a prise, et ce qu'il advient quand
-- personne ne la prend.
--
-- Décisions portées par cette migration :
--
--   1. Toute rupture est adressée à UN distributeur, qui agit. Le fabricant la
--      voit en lecture, sur son seul catalogue. Son interface actuelle reste
--      donc valable telle quelle.
--   2. Un fabricant qui livre lui-même possède son propre distributeur, marqué
--      `auto_distribution`. Les trois cas de terrain (distributeur affilié,
--      distributeur indépendant, fabricant qui distribue) sont ainsi absorbés
--      sans aucun cas particulier dans le code.
--   3. Escalade en cercles. Passé `delai_escalade()`, la rupture s'ouvre aux
--      autres distributeurs qui portent le même fabricant dans la même commune.
--      Passé `delai_peremption()`, elle est close en `non_servie`.
--
-- Le point structurant : la résolution du destinataire est un trigger SQL
-- BEFORE INSERT, pas du code applicatif. La rupture la plus importante du
-- produit, celle que la caisse déclenche quand une vente vide un stock, est
-- créée par le trigger de 006 et ne passe jamais par NestJS. Router côté
-- TypeScript aurait laissé ces ruptures sans destinataire.

-- ── 1. Nouvelles valeurs d'énumération ──────────────────────────────────────
-- `db:provision` et `db:migrate` appellent psql sans -1 : chaque instruction est
-- validée séparément, une valeur ajoutée ici est donc utilisable plus bas.

ALTER TYPE role_utilisateur ADD VALUE IF NOT EXISTS 'distributeur';

-- Statut terminal qui manquait. Sans lui, une rupture que personne ne prend
-- reste « ouverte » indéfiniment et le taux de service ne se mesure pas. Or
-- c'est l'indicateur que Yalla vend au fabricant.
ALTER TYPE statut_rupture ADD VALUE IF NOT EXISTS 'non_servie';

ALTER TYPE cible_notification ADD VALUE IF NOT EXISTS 'distributeurs';

-- ── 2. Le distributeur ──────────────────────────────────────────────────────

CREATE TABLE distributeurs (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Nullable, contrairement aux autres tables de rôle. Un distributeur
  -- d'auto-distribution représente un fabricant qui livre lui-même, et ce
  -- fabricant possède déjà un compte de connexion en tant que fabricant.
  -- Lui en créer un second serait faux. Un distributeur recensé sur le terrain
  -- mais pas encore inscrit est dans le même cas.
  utilisateur_id    UUID UNIQUE REFERENCES utilisateurs(id) ON DELETE SET NULL,
  -- NULL = distributeur indépendant, il travaille plusieurs marques et n'est la
  -- propriété d'aucune. Renseigné = affilié à ce fabricant, ou auto-distribution.
  fabricant_id      UUID REFERENCES fabricants(id) ON DELETE CASCADE,
  nom               TEXT NOT NULL,
  telephone         TEXT,
  auto_distribution BOOLEAN NOT NULL DEFAULT false,
  statut            statut_fabricant NOT NULL DEFAULT 'actif',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_auto_distribution_rattachee
    CHECK (NOT auto_distribution OR fabricant_id IS NOT NULL)
);

CREATE INDEX idx_distributeurs_fabricant ON distributeurs(fabricant_id);
CREATE INDEX idx_distributeurs_statut ON distributeurs(statut);

-- Un fabricant n'a qu'un seul distributeur d'auto-distribution.
CREATE UNIQUE INDEX idx_distributeurs_auto_unique
  ON distributeurs(fabricant_id) WHERE auto_distribution;

CREATE TRIGGER trg_distributeurs_updated_at
  BEFORE UPDATE ON distributeurs
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ── 3. Qui dessert quelle boutique, pour quel fabricant ─────────────────────
-- `attributions_reseau` disait « ce fabricant couvre cette boutique ». Elle dit
-- maintenant aussi par quelle main. Une même boutique peut être desservie par un
-- distributeur pour une marque et par un autre pour une autre marque : c'est la
-- réalité de la distribution de proximité à Abidjan, et le triplet la porte.
--
-- La colonne reste nullable : une attribution sans distributeur désigné produit
-- une rupture sans destinataire, qui part au cercle élargi dès l'escalade
-- plutôt que de se perdre.

ALTER TABLE attributions_reseau
  ADD COLUMN distributeur_id UUID REFERENCES distributeurs(id) ON DELETE SET NULL;

CREATE INDEX idx_attributions_distributeur ON attributions_reseau(distributeur_id);

-- ── 4. Le livreur dépend du distributeur, plus du fabricant ─────────────────
-- Un livreur n'a jamais été l'employé d'une marque, il est l'employé de celui
-- qui distribue. Avec l'auto-distribution, le cas « livreur du fabricant » reste
-- exprimable sans conserver deux rattachements concurrents.

ALTER TABLE livreurs
  ADD COLUMN distributeur_id UUID REFERENCES distributeurs(id) ON DELETE RESTRICT;

-- Reprise des livreurs déjà en base : chaque fabricant qui en avait reçoit son
-- distributeur d'auto-distribution, et ses livreurs y sont rattachés. Sur une
-- base neuve, ces deux instructions ne touchent aucune ligne.
INSERT INTO distributeurs (fabricant_id, nom, auto_distribution)
SELECT DISTINCT f.id, f.nom || ' (distribution interne)', true
FROM fabricants f
JOIN livreurs l ON l.fabricant_id = f.id
WHERE NOT EXISTS (
  SELECT 1 FROM distributeurs d
  WHERE d.fabricant_id = f.id AND d.auto_distribution
);

UPDATE livreurs l
SET distributeur_id = d.id
FROM distributeurs d
WHERE d.fabricant_id = l.fabricant_id
  AND d.auto_distribution
  AND l.distributeur_id IS NULL;

ALTER TABLE livreurs ALTER COLUMN distributeur_id SET NOT NULL;

-- Deux vues de 008 lisent encore `livreurs.fabricant_id`. PostgreSQL refuse de
-- supprimer une colonne dont une vue dépend, il faut donc les redéfinir d'abord.
-- CREATE OR REPLACE suffit : les colonnes existantes gardent leur nom, leur type
-- et leur ordre, et la dépendance à l'ancienne colonne disparaît avec l'ancienne
-- définition.
--
-- LIMITE ASSUMÉE, à trancher séparément : le chiffre d'affaires d'un fabricant
-- ne compte que les livraisons des distributeurs qui lui sont rattachés, y
-- compris son auto-distribution. Les ventes réalisées sur ses produits par un
-- distributeur indépendant n'y figurent pas. C'est la traduction littérale de
-- l'ancienne définition, qui rattachait le livreur au fabricant. Une définition
-- fondée sur les ruptures servies donnerait un autre résultat, et c'est une
-- décision de métrique, pas de routage.
CREATE OR REPLACE VIEW v_chiffre_affaires_par_fabricant AS
SELECT
  f.id AS fabricant_id,
  f.nom AS fabricant_nom,
  COALESCE(SUM(l.montant) FILTER (WHERE l.statut = 'terminee'), 0) AS chiffre_affaires
FROM fabricants f
LEFT JOIN distributeurs d ON d.fabricant_id = f.id
LEFT JOIN livreurs lv ON lv.distributeur_id = d.id
LEFT JOIN livraisons l ON l.livreur_id = lv.id
GROUP BY f.id, f.nom;

CREATE OR REPLACE VIEW v_chiffre_affaires_par_livreur AS
SELECT
  lv.id AS livreur_id,
  u.nom AS livreur_nom,
  -- Nul quand le livreur dépend d'un distributeur indépendant : il ne roule
  -- alors pour aucune marque en particulier.
  d.fabricant_id,
  COALESCE(SUM(l.montant) FILTER (WHERE l.statut = 'terminee'), 0) AS chiffre_affaires,
  COUNT(l.id) FILTER (WHERE l.statut = 'terminee') AS nombre_livraisons,
  d.id AS distributeur_id
FROM livreurs lv
JOIN utilisateurs u ON u.id = lv.utilisateur_id
JOIN distributeurs d ON d.id = lv.distributeur_id
LEFT JOIN livraisons l ON l.livreur_id = lv.id
GROUP BY lv.id, u.nom, d.fabricant_id, d.id;

ALTER TABLE livreurs DROP COLUMN fabricant_id;

CREATE INDEX idx_livreurs_distributeur ON livreurs(distributeur_id);

-- ── 5. La rupture enregistre enfin ses acteurs ──────────────────────────────
-- Avant cette migration, une rupture passait de `signalee` à `prise_en_charge`
-- sans jamais dire à qui elle avait été envoyée ni qui l'avait prise. Aucun
-- délai n'était donc mesurable, et aucune escalade n'était déclenchable.

ALTER TABLE ruptures
  ADD COLUMN distributeur_id UUID REFERENCES distributeurs(id) ON DELETE SET NULL;

ALTER TABLE ruptures
  ADD COLUMN livreur_id UUID REFERENCES livreurs(id) ON DELETE SET NULL;

ALTER TABLE ruptures
  ADD COLUMN date_prise_en_charge TIMESTAMPTZ;

ALTER TABLE ruptures
  ADD COLUMN escaladee_le TIMESTAMPTZ;

CREATE INDEX idx_ruptures_distributeur ON ruptures(distributeur_id);
CREATE INDEX idx_ruptures_livreur ON ruptures(livreur_id);
-- Index de travail du job d'escalade : il ne balaie que les ruptures encore libres.
CREATE INDEX idx_ruptures_escalade
  ON ruptures(date_signalement) WHERE statut = 'signalee';

-- ── 6. Les deux délais ──────────────────────────────────────────────────────
-- Des fonctions et non des colonnes de configuration : les ajuster ne demande
-- qu'un CREATE OR REPLACE, sans migration de schéma, sans redémarrage de l'API
-- et sans écran d'administration à construire. Si le pilote d'Abidjan montre que
-- deux heures sont trop longues, la correction tient en une ligne.

CREATE OR REPLACE FUNCTION delai_escalade() RETURNS INTERVAL
  LANGUAGE sql IMMUTABLE AS $fn$ SELECT INTERVAL '2 hours' $fn$;

CREATE OR REPLACE FUNCTION delai_peremption() RETURNS INTERVAL
  LANGUAGE sql IMMUTABLE AS $fn$ SELECT INTERVAL '24 hours' $fn$;

-- ── 7. Résolution du destinataire, à l'insertion ────────────────────────────
-- Ce trigger est la pièce maîtresse. Il s'applique aux DEUX chemins de création
-- d'une rupture : le signalement manuel depuis l'app Point de vente, et le
-- signalement automatique émis par le trigger de caisse de 006. Écrire cette
-- logique dans le service NestJS aurait couvert le premier et manqué le second,
-- c'est-à-dire justement le mécanisme central du produit.

CREATE OR REPLACE FUNCTION resoudre_destinataire_rupture()
RETURNS TRIGGER AS $fn$
BEGIN
  IF NEW.distributeur_id IS NULL THEN
    SELECT ar.distributeur_id INTO NEW.distributeur_id
    FROM attributions_reseau ar
    JOIN produits p ON p.fabricant_id = ar.fabricant_id
    WHERE ar.point_de_vente_id = NEW.point_de_vente_id
      AND p.id = NEW.produit_id
      AND ar.distributeur_id IS NOT NULL
    LIMIT 1;
  END IF;
  RETURN NEW;
END;
$fn$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ruptures_resout_destinataire
  BEFORE INSERT ON ruptures
  FOR EACH ROW EXECUTE FUNCTION resoudre_destinataire_rupture();

-- ── 8. Escalade et péremption ───────────────────────────────────────────────
-- Fonction idempotente, sans effet si rien n'a dépassé les délais. Elle est
-- appelée périodiquement par l'API (EscaladeService) et peut l'être à la main
-- ou par pg_cron sans rien changer.

CREATE OR REPLACE FUNCTION escalader_ruptures_en_attente()
RETURNS TABLE (rupture_id UUID, action TEXT) AS $fn$
BEGIN
  -- Deux instructions séparées, et non deux CTE d'une même requête : dans une
  -- requête unique, les deux UPDATE partageraient le même instantané et
  -- pourraient viser la même ligne deux fois, ce que PostgreSQL ne garantit pas.
  RETURN QUERY
  UPDATE ruptures
  SET escaladee_le = now()
  WHERE statut = 'signalee'
    AND escaladee_le IS NULL
    AND date_signalement < now() - delai_escalade()
  RETURNING id, 'escaladee'::TEXT;

  -- Une rupture doit d'abord avoir été escaladée pour pouvoir périmer. Si le job
  -- est resté à l'arrêt plus longtemps que le délai de péremption, une même
  -- rupture peut être escaladée puis périmée dans la même passe : c'est voulu.
  RETURN QUERY
  UPDATE ruptures
  SET statut = 'non_servie',
      date_resolution = now()
  WHERE statut = 'signalee'
    AND escaladee_le IS NOT NULL
    AND date_signalement < now() - delai_peremption()
  RETURNING id, 'perimee'::TEXT;

  RETURN;
END;
$fn$ LANGUAGE plpgsql;

-- ── 9. Vues ────────────────────────────────────────────────────────────────
-- `v_ruptures_ouvertes` conserve ses colonnes et leur ordre, CREATE OR REPLACE
-- n'autorisant que l'ajout en fin de liste.

CREATE OR REPLACE VIEW v_ruptures_ouvertes AS
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
  r.date_prise_en_charge
FROM ruptures r
JOIN points_de_vente pdv ON pdv.id = r.point_de_vente_id
JOIN produits p ON p.id = r.produit_id
WHERE r.statut IN ('signalee', 'prise_en_charge');

-- Qui a le droit de voir, et donc de prendre, une rupture encore libre.
--
-- Cercle « attribue » : le distributeur désigné pour cette boutique et ce
-- fabricant, dès la seconde du signalement.
--
-- Cercle « elargi » : après escalade seulement, tout distributeur qui porte déjà
-- le même fabricant dans la même commune. La restriction au même fabricant n'est
-- pas une contrainte technique, c'est une protection commerciale : en Côte
-- d'Ivoire la distribution est territoriale, et proposer une rupture à un
-- distributeur qui ne travaille pas cette marque casserait un accord au lieu de
-- rendre service.
CREATE VIEW v_acces_rupture_distributeur AS
SELECT r.id AS rupture_id, r.distributeur_id, 'attribue'::TEXT AS cercle
FROM ruptures r
WHERE r.statut = 'signalee'
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
  AND r.escaladee_le IS NOT NULL
  AND ar.distributeur_id IS NOT NULL
  AND ar.distributeur_id IS DISTINCT FROM r.distributeur_id;

-- Le chiffre d'affaires réellement généré sur les produits d'un fabricant, quel
-- que soit le distributeur qui a servi la rupture.
--
-- `v_chiffre_affaires_par_fabricant` répond à « que rapporte MON réseau ? » et
-- ne compte que les distributeurs rattachés. Cette vue-ci répond à « que
-- rapporte MA MARQUE ? » et compte tout, distributeurs indépendants compris.
-- Les deux sont justes, elles ne mesurent simplement pas la même chose, et
-- l'écart entre elles est en soi une information commerciale : il dit quelle
-- part de la distribution du fabricant lui échappe.
--
-- Contrepartie assumée : ne comptent ici que les livraisons rattachées à une
-- rupture (`livraisons.rupture_id`). Une livraison de réassort spontané, sans
-- rupture signalée, n'y figure pas.
CREATE VIEW v_chiffre_affaires_genere_par_fabricant AS
SELECT
  p.fabricant_id,
  f.nom AS fabricant_nom,
  COALESCE(SUM(l.montant) FILTER (WHERE l.statut = 'terminee'), 0) AS chiffre_affaires,
  COALESCE(SUM(l.montant) FILTER (
    WHERE l.statut = 'terminee' AND d.fabricant_id IS DISTINCT FROM p.fabricant_id
  ), 0) AS dont_distributeurs_non_rattaches,
  COUNT(l.id) FILTER (WHERE l.statut = 'terminee') AS nombre_livraisons
FROM produits p
JOIN fabricants f ON f.id = p.fabricant_id
LEFT JOIN ruptures r ON r.produit_id = p.id
LEFT JOIN livraisons l ON l.rupture_id = r.id
LEFT JOIN livreurs lv ON lv.id = l.livreur_id
LEFT JOIN distributeurs d ON d.id = lv.distributeur_id
GROUP BY p.fabricant_id, f.nom;

-- Taux de service : l'indicateur que Yalla vend au fabricant. Il n'était pas
-- calculable avant que `non_servie` et les horodatages existent.
CREATE VIEW v_taux_de_service_par_fabricant AS
SELECT
  p.fabricant_id,
  count(*) AS ruptures_closes,
  count(*) FILTER (WHERE r.statut = 'resolue') AS ruptures_servies,
  round(
    100.0 * count(*) FILTER (WHERE r.statut = 'resolue') / NULLIF(count(*), 0),
    1
  ) AS taux_de_service_pct,
  avg(r.date_prise_en_charge - r.date_signalement)
    FILTER (WHERE r.date_prise_en_charge IS NOT NULL) AS delai_moyen_prise_en_charge
FROM ruptures r
JOIN produits p ON p.id = r.produit_id
WHERE r.statut IN ('resolue', 'non_servie')
GROUP BY p.fabricant_id;
