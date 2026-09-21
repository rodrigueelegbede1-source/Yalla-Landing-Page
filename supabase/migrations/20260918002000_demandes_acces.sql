-- 20260918002000_demandes_acces.sql
--
-- L'inscription des professionnels depuis le site, et sa validation par
-- l'administrateur.
--
-- ── CE QUE CELA CHANGE AU MODÈLE D'ACQUISITION ──────────────────────────────
--
-- Jusqu'ici tout compte était créé en main propre : l'agent recenseur inscrit
-- une boutique sur le pas de sa porte, le distributeur enrôle son livreur et
-- lui dicte son mot de passe. C'est ce qui permet de se passer de SMS, donc de
-- coût par connexion, et ce qui garantit qu'il y a une vraie personne derrière
-- chaque compte.
--
-- Un formulaire public ouvre une seconde porte, et il faut en mesurer la
-- conséquence : n'importe qui peut la pousser. D'où le choix d'une DEMANDE
-- plutôt que d'un compte. Rien n'est créé tant que l'administrateur n'a pas
-- validé, et c'est lui qui déclenche la création par les fonctions existantes.
--
-- ── POURQUOI PAS DE COMPTE EN ATTENTE ───────────────────────────────────────
--
-- Il serait plus simple de créer le compte immédiatement avec un statut
-- « en attente ». Ce serait une erreur : un compte non validé peut se
-- connecter, et un compte qui se connecte sans rien voir est une source de
-- confusion et de support. Une demande n'est pas un compte, elle vit dans sa
-- propre table et ne donne accès à rien.
--
-- ── LE MOT DE PASSE N'EST PAS DEMANDÉ ICI ───────────────────────────────────
--
-- Le demandeur ne le choisit pas : il lui est remis à la validation, comme pour
-- tous les autres comptes du réseau. Stocker un mot de passe dans une table de
-- demandes, en clair ou non, serait un risque gratuit pour un compte qui
-- n'existera peut-être jamais.

CREATE TYPE profil_demande AS ENUM (
  'fabricant',
  'distributeur_affilie',
  'distributeur_independant'
);

COMMENT ON TYPE profil_demande IS
  'Le profil déclaré à l''inscription. « Affilié » et « indépendant » ne sont pas deux rôles distincts mais la présence ou non de distributeurs.fabricant_id.';

CREATE TYPE statut_demande AS ENUM (
  'en_attente',
  'validee',
  'refusee'
);

CREATE TABLE demandes_acces (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profil           profil_demande NOT NULL,
  statut           statut_demande NOT NULL DEFAULT 'en_attente',

  -- La personne qui demande, et l'entreprise qu'elle représente.
  nom              TEXT NOT NULL,
  societe          TEXT NOT NULL,
  telephone        TEXT NOT NULL,
  email            TEXT,

  -- Ce qui permet à l'administrateur de décider sans rappeler.
  ville            TEXT,
  communes         TEXT,
  marques          TEXT,
  message          TEXT,

  -- Renseigné à la validation : le compte effectivement créé.
  utilisateur_id   UUID REFERENCES utilisateurs(id) ON DELETE SET NULL,
  traitee_le       TIMESTAMPTZ,
  traitee_par      UUID REFERENCES utilisateurs(id) ON DELETE SET NULL,
  motif_refus      TEXT,

  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_demandes_statut ON demandes_acces(statut, created_at DESC);

-- Une même personne ne peut avoir qu'une demande en cours. Sans cela, un
-- formulaire renvoyé trois fois par impatience produit trois demandes
-- identiques que l'administrateur doit démêler.
CREATE UNIQUE INDEX idx_demandes_telephone_en_attente
  ON demandes_acces(normaliser_telephone(telephone))
  WHERE statut = 'en_attente';

CREATE TRIGGER trg_demandes_updated_at
  BEFORE UPDATE ON demandes_acces
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE demandes_acces ENABLE ROW LEVEL SECURITY;

-- Seul l'administrateur lit les demandes. Le formulaire, lui, n'écrit pas
-- directement dans la table : il passe par la fonction ci-dessous.
CREATE POLICY demandes_admin ON demandes_acces FOR ALL TO authenticated
  USING (est_admin()) WITH CHECK (est_admin());

-- ── Déposer une demande ─────────────────────────────────────────────────────
--
-- `SECURITY DEFINER` et ouverte à `anon` : c'est le seul point de tout le
-- schéma qu'un visiteur non authentifié peut atteindre en écriture. Elle est
-- donc volontairement étroite :
--
--   * elle n'écrit que dans `demandes_acces`, jamais dans une table métier ;
--   * elle ne rend qu'un accusé de réception, aucune donnée existante, pour ne
--     pas devenir un moyen de savoir qui est déjà inscrit ;
--   * un numéro déjà en attente rend le même accusé plutôt qu'une erreur, ce
--     qui évite à la fois le doublon et la divulgation.
CREATE OR REPLACE FUNCTION deposer_demande_acces(
  p_profil    TEXT,
  p_nom       TEXT,
  p_societe   TEXT,
  p_telephone TEXT,
  p_email     TEXT DEFAULT NULL,
  p_ville     TEXT DEFAULT NULL,
  p_communes  TEXT DEFAULT NULL,
  p_marques   TEXT DEFAULT NULL,
  p_message   TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_tel     TEXT;
  v_profil  profil_demande;
  v_id      UUID;
BEGIN
  IF p_profil NOT IN ('fabricant', 'distributeur_affilie', 'distributeur_independant') THEN
    RAISE EXCEPTION 'Profil inconnu' USING ERRCODE = 'check_violation';
  END IF;
  v_profil := p_profil::profil_demande;

  v_tel := normaliser_telephone(p_telephone);
  IF v_tel IS NULL OR length(v_tel) <> 13 OR left(v_tel, 3) <> '225' THEN
    RAISE EXCEPTION 'Numéro de téléphone invalide' USING ERRCODE = 'check_violation';
  END IF;

  IF length(trim(COALESCE(p_nom, ''))) < 3 THEN
    RAISE EXCEPTION 'Nom trop court' USING ERRCODE = 'check_violation';
  END IF;
  IF length(trim(COALESCE(p_societe, ''))) < 2 THEN
    RAISE EXCEPTION 'Nom de société manquant' USING ERRCODE = 'check_violation';
  END IF;

  -- Demande déjà en cours pour ce numéro : on rend le même accusé. Répondre
  -- « vous avez déjà demandé » apprendrait à un tiers qu'un numéro est inscrit.
  SELECT id INTO v_id
    FROM demandes_acces
   WHERE normaliser_telephone(telephone) = v_tel AND statut = 'en_attente';

  IF v_id IS NULL THEN
    INSERT INTO demandes_acces (profil, nom, societe, telephone, email,
                                ville, communes, marques, message)
    VALUES (v_profil,
            trim(p_nom),
            trim(p_societe),
            v_tel,
            NULLIF(trim(COALESCE(p_email, '')), ''),
            NULLIF(trim(COALESCE(p_ville, '')), ''),
            NULLIF(trim(COALESCE(p_communes, '')), ''),
            NULLIF(trim(COALESCE(p_marques, '')), ''),
            NULLIF(trim(COALESCE(p_message, '')), ''))
    RETURNING id INTO v_id;
  END IF;

  RETURN jsonb_build_object('recue', true, 'demande_id', v_id);
END;
$fn$;

COMMENT ON FUNCTION deposer_demande_acces IS
  'Seul point d''écriture ouvert à un visiteur non authentifié. N''écrit que dans demandes_acces et ne rend aucune donnée existante.';

REVOKE EXECUTE ON FUNCTION deposer_demande_acces FROM PUBLIC;
GRANT EXECUTE ON FUNCTION deposer_demande_acces TO anon, authenticated;

-- ── Ce que l'administrateur voit ────────────────────────────────────────────

CREATE VIEW v_demandes_acces
WITH (security_invoker = on) AS
SELECT
  d.id AS demande_id,
  d.profil,
  d.statut,
  d.nom,
  d.societe,
  d.telephone,
  d.email,
  d.ville,
  d.communes,
  d.marques,
  d.message,
  d.created_at,
  d.traitee_le,
  d.motif_refus,
  u.nom AS compte_cree,
  EXTRACT(EPOCH FROM (now() - d.created_at))::INTEGER AS anciennete_secondes
FROM demandes_acces d
LEFT JOIN utilisateurs u ON u.id = d.utilisateur_id;

-- ── Refuser ─────────────────────────────────────────────────────────────────
--
-- La validation, elle, n'est pas une fonction SQL : créer le compte exige la
-- clé de service, donc elle passe par la fonction Edge `creer-compte`, qui
-- appelle ensuite `marquer_demande_validee`. Refuser ne crée rien et reste ici.

CREATE OR REPLACE FUNCTION refuser_demande_acces(
  p_demande_id UUID,
  p_motif      TEXT DEFAULT NULL
)
RETURNS demandes_acces
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_demande demandes_acces;
BEGIN
  IF NOT est_admin() THEN
    RAISE EXCEPTION 'Réservé à l''administrateur' USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE demandes_acces
     SET statut = 'refusee',
         motif_refus = NULLIF(trim(COALESCE(p_motif, '')), ''),
         traitee_le = now(),
         traitee_par = auth_utilisateur_id()
   WHERE id = p_demande_id AND statut = 'en_attente'
  RETURNING * INTO v_demande;

  IF v_demande.id IS NULL THEN
    RAISE EXCEPTION 'Demande introuvable ou déjà traitée' USING ERRCODE = 'no_data_found';
  END IF;

  RETURN v_demande;
END;
$fn$;

CREATE OR REPLACE FUNCTION marquer_demande_validee(
  p_demande_id     UUID,
  p_utilisateur_id UUID
)
RETURNS demandes_acces
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_demande demandes_acces;
BEGIN
  IF NOT est_admin() THEN
    RAISE EXCEPTION 'Réservé à l''administrateur' USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE demandes_acces
     SET statut = 'validee',
         utilisateur_id = p_utilisateur_id,
         traitee_le = now(),
         traitee_par = auth_utilisateur_id()
   WHERE id = p_demande_id AND statut = 'en_attente'
  RETURNING * INTO v_demande;

  IF v_demande.id IS NULL THEN
    RAISE EXCEPTION 'Demande introuvable ou déjà traitée' USING ERRCODE = 'no_data_found';
  END IF;

  RETURN v_demande;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION refuser_demande_acces, marquer_demande_validee
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION refuser_demande_acces, marquer_demande_validee
  TO authenticated;

-- ── Ce que le fabricant verra sur son tableau de bord ───────────────────────
--
-- Le rôle fabricant n'a aucune interface à ce jour. La vue existe donc avant
-- l'écran, parce que c'est elle qui décide de ce qu'il y aura à montrer : le
-- taux de service est l'indicateur vendu, et il est calculable depuis la
-- migration du distributeur.
CREATE VIEW v_tableau_de_bord_fabricant
WITH (security_invoker = on) AS
SELECT
  f.id   AS fabricant_id,
  f.nom  AS fabricant_nom,
  (SELECT count(*) FROM produits p WHERE p.fabricant_id = f.id AND p.disponible) AS produits,
  (SELECT count(DISTINCT ar.point_de_vente_id)
     FROM attributions_reseau ar WHERE ar.fabricant_id = f.id) AS boutiques,
  (SELECT count(DISTINCT ar.distributeur_id)
     FROM attributions_reseau ar
    WHERE ar.fabricant_id = f.id AND ar.distributeur_id IS NOT NULL) AS distributeurs,
  (SELECT count(*)
     FROM ruptures r JOIN produits p ON p.id = r.produit_id
    WHERE p.fabricant_id = f.id AND r.statut = 'signalee'
      AND r.confirmee_le IS NOT NULL) AS ruptures_ouvertes,
  ts.ruptures_closes,
  ts.ruptures_servies,
  ts.taux_de_service_pct,
  ts.delai_moyen_prise_en_charge,
  ca.chiffre_affaires,
  ca.dont_distributeurs_non_rattaches
FROM fabricants f
LEFT JOIN v_taux_de_service_par_fabricant ts ON ts.fabricant_id = f.id
LEFT JOIN v_chiffre_affaires_genere_par_fabricant ca ON ca.fabricant_id = f.id;

COMMENT ON VIEW v_tableau_de_bord_fabricant IS
  'Ce qu''un fabricant a besoin de voir. Le taux de service est l''indicateur vendu ; l''écart entre les deux mesures de chiffre d''affaires dit quelle part de sa distribution lui échappe.';

-- Le fabricant doit pouvoir lire sa propre ligne. `fabricants` était déjà
-- lisible de tous les comptes authentifiés, mais rien ne liait un compte
-- fabricant à SES données : les vues agrégées restaient inaccessibles faute de
-- politique sur les tables qu'elles traversent.
CREATE POLICY ruptures_fabricant ON ruptures FOR SELECT TO authenticated
  USING (
    auth_role() = 'fabricant'
    AND EXISTS (
      SELECT 1 FROM produits p
       WHERE p.id = ruptures.produit_id
         AND p.fabricant_id = auth_id_metier()
    )
  );

CREATE POLICY attributions_fabricant ON attributions_reseau FOR SELECT TO authenticated
  USING (
    auth_role() = 'fabricant'
    AND fabricant_id = auth_id_metier()
  );

CREATE POLICY livraisons_fabricant ON livraisons FOR SELECT TO authenticated
  USING (
    auth_role() = 'fabricant'
    AND EXISTS (
      SELECT 1 FROM ruptures r
        JOIN produits p ON p.id = r.produit_id
       WHERE r.id = livraisons.rupture_id
         AND p.fabricant_id = auth_id_metier()
    )
  );

-- LE FABRICANT NE VOIT TOUJOURS NI LES VENTES NI LES STOCKS. C'est la promesse
-- faite au boutiquier, et elle ne souffre pas d'exception : il voit les
-- ruptures nées sur ses produits, pas le chiffre d'affaires de la boutique.
