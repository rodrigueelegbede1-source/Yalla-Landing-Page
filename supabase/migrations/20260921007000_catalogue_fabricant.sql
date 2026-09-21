-- 20260921007000_catalogue_fabricant.sql
--
-- Le fabricant gère enfin son propre catalogue.
--
-- ── CE QUI MANQUAIT, ET CE QUE CELA COÛTAIT ─────────────────────────────────
--
-- `produits` n'avait que deux politiques : tout le monde lit, l'administrateur
-- écrit. Un fabricant ne pouvait donc rien faire de son propre catalogue :
-- ni ajouter une référence, ni corriger un libellé, ni retirer un produit
-- arrêté. Tout passait par un script d'import lancé depuis un poste de
-- développement.
--
-- Pour le pilote, cela tenait : SDTM-CI a été inscrit avec ses trente
-- références en une fois. Cela ne tient plus dès le deuxième fabricant, et
-- surtout cela contredit ce qu'on lui vend. On demande à un industriel de
-- confier sa marque à une plateforme, et on lui répond que pour ajouter un
-- format il faut écrire à l'éditeur.
--
-- ── LE PÉRIMÈTRE, QUI EST TOUT L'ENJEU ──────────────────────────────────────
--
-- Un fabricant écrit SUR SON CATALOGUE, et sur rien d'autre. La tentation
-- serait d'ouvrir `produits` en écriture au rôle `fabricant` avec un
-- `WITH CHECK (fabricant_id = auth_id_metier())`. Ce serait presque juste, et
-- le « presque » est le problème : une politique d'UPDATE dont seul le
-- `WITH CHECK` filtre laisse modifier une ligne qui ne vous appartient pas à
-- condition de vous l'attribuer au passage. Il faut les deux, `USING` pour
-- dire quelles lignes sont touchables et `WITH CHECK` pour dire ce qu'elles
-- ont le droit de devenir.
--
-- ── LA RÉFÉRENCE NE SE RÉÉCRIT PAS ──────────────────────────────────────────
--
-- Elle sert au distributeur à retrouver un produit sur un bon de livraison, et
-- elle est imprimée sur des bons déjà partis. La changer après coup rendrait
-- illisibles des documents papier que personne ne peut corriger. Un produit
-- dont la référence était fausse se retire et se recrée.

-- ── 1. Écriture sur son propre catalogue ────────────────────────────────────

CREATE POLICY produits_fabricant_ecrit ON produits FOR INSERT TO authenticated
  WITH CHECK (auth_role() = 'fabricant' AND fabricant_id = auth_id_metier());

-- USING ET WITH CHECK, les deux. Voir l'explication en tête de fichier : sans
-- le USING, on peut modifier la ligne d'un concurrent en se l'attribuant.
CREATE POLICY produits_fabricant_modifie ON produits FOR UPDATE TO authenticated
  USING      (auth_role() = 'fabricant' AND fabricant_id = auth_id_metier())
  WITH CHECK (auth_role() = 'fabricant' AND fabricant_id = auth_id_metier());

-- Pas de politique de SUPPRESSION, et c'est délibéré. Un produit supprimé
-- emporterait avec lui, par cascade, les ruptures et les stocks qui le
-- référencent : l'historique du réseau disparaîtrait pour cause de ménage dans
-- un catalogue. `disponible = false` le retire des écrans sans rien détruire.

-- Les catégories sont communes à tout le réseau. Un fabricant en crée une si
-- la sienne manque, mais ne peut ni renommer ni supprimer celles des autres :
-- « Riz » renommé par un concurrent déplacerait les produits de chacun.
CREATE POLICY categories_fabricant_ajoute ON categories_produit FOR INSERT TO authenticated
  WITH CHECK (auth_role() = 'fabricant');

-- ── 2. Écrire un produit ────────────────────────────────────────────────────
--
-- Une fonction plutôt qu'un INSERT direct, pour trois raisons qui tiennent
-- toutes à ce qui se passe sur le terrain :
--
--   * la RÉFÉRENCE se fabrique toute seule si on ne la donne pas. Sur le
--     pilote, aucun fabricant n'a fourni ses références carton, et en inventer
--     à la main produit des doublons et des fautes de frappe.
--   * la CATÉGORIE se crée si elle n'existe pas, par son nom. Obliger à
--     choisir dans une liste déroulante qui ne contient pas encore « Pâtes »
--     bloque la saisie pour rien.
--   * le contrôle d'unicité rend un message lisible, là où la contrainte de
--     base rend « duplicate key value violates unique constraint
--     idx_produits_fabricant_reference », que personne ne peut interpréter.

CREATE OR REPLACE FUNCTION enregistrer_produit(
  p_nom        TEXT,
  p_categorie  TEXT DEFAULT NULL,
  p_reference  TEXT DEFAULT NULL,
  p_produit_id UUID DEFAULT NULL,
  p_disponible BOOLEAN DEFAULT true
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_fabricant  UUID := auth_id_metier();
  v_nom        TEXT := trim(COALESCE(p_nom, ''));
  v_categorie  TEXT := NULLIF(trim(COALESCE(p_categorie, '')), '');
  v_ref        TEXT := NULLIF(upper(trim(COALESCE(p_reference, ''))), '');
  v_cat_id     UUID;
  v_id         UUID;
  v_initiales  TEXT;
  v_compteur   INTEGER := 0;
BEGIN
  IF auth_role() <> 'fabricant' OR v_fabricant IS NULL THEN
    RAISE EXCEPTION 'Réservé au fabricant, sur son propre catalogue'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF length(v_nom) < 2 THEN
    RAISE EXCEPTION 'Le nom du produit est obligatoire' USING ERRCODE = 'check_violation';
  END IF;

  -- La catégorie, retrouvée sans tenir compte de la casse ni des espaces, ou
  -- créée. Deux catégories « Boissons » et « boissons » côte à côte dans une
  -- liste déroulante sont une source d'erreur permanente.
  IF v_categorie IS NOT NULL THEN
    SELECT id INTO v_cat_id FROM categories_produit
     WHERE lower(nom) = lower(v_categorie) LIMIT 1;
    IF v_cat_id IS NULL THEN
      INSERT INTO categories_produit (nom) VALUES (v_categorie) RETURNING id INTO v_cat_id;
    END IF;
  END IF;

  -- ── Modification d'un produit existant ────────────────────────────────────
  IF p_produit_id IS NOT NULL THEN
    UPDATE produits
       SET nom = v_nom,
           categorie_id = COALESCE(v_cat_id, categorie_id),
           disponible = p_disponible
     WHERE id = p_produit_id AND fabricant_id = v_fabricant
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN
      RAISE EXCEPTION 'Produit introuvable dans votre catalogue'
        USING ERRCODE = 'no_data_found';
    END IF;

    RETURN jsonb_build_object('produit_id', v_id, 'cree', false);
  END IF;

  -- ── Création ──────────────────────────────────────────────────────────────
  --
  -- LA RÉFÉRENCE FABRIQUÉE. Elle doit rester lisible : c'est elle que le
  -- distributeur cherche des yeux sur un bon de livraison. On prend les
  -- initiales de la marque, puis les premières lettres du produit et le
  -- premier nombre qu'il contient, qui est presque toujours le grammage.
  IF v_ref IS NULL THEN
    SELECT upper(substring(regexp_replace(f.nom, '[^A-Za-z]', '', 'g') from 1 for 4))
      INTO v_initiales FROM fabricants f WHERE f.id = v_fabricant;

    v_ref := COALESCE(NULLIF(v_initiales, ''), 'PROD')
          || '-'
          || upper(substring(regexp_replace(v_nom, '[^A-Za-z]', '', 'g') from 1 for 3))
          || COALESCE((regexp_match(v_nom, '([0-9]+)'))[1], '');

    -- Un suffixe numérique tant que la référence est prise. Sans cette boucle,
    -- deux formats du même produit se heurteraient sur la même référence et le
    -- second ne serait jamais créé.
    WHILE EXISTS (
      SELECT 1 FROM produits WHERE fabricant_id = v_fabricant AND reference = v_ref
    ) LOOP
      v_compteur := v_compteur + 1;
      v_ref := regexp_replace(v_ref, '-[0-9]+$', '') || '-' || v_compteur::TEXT;
      IF v_compteur > 99 THEN
        RAISE EXCEPTION 'Impossible de fabriquer une référence libre'
          USING ERRCODE = 'check_violation';
      END IF;
    END LOOP;
  ELSIF EXISTS (
    SELECT 1 FROM produits WHERE fabricant_id = v_fabricant AND reference = v_ref
  ) THEN
    RAISE EXCEPTION 'La référence « % » existe déjà dans votre catalogue', v_ref
      USING ERRCODE = 'unique_violation';
  END IF;

  INSERT INTO produits (fabricant_id, nom, reference, categorie_id, disponible)
  VALUES (v_fabricant, v_nom, v_ref, v_cat_id, p_disponible)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('produit_id', v_id, 'reference', v_ref, 'cree', true);
END;
$fn$;

REVOKE EXECUTE ON FUNCTION enregistrer_produit FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION enregistrer_produit TO authenticated;

-- ── 3. Ce que le fabricant voit de son catalogue ────────────────────────────

CREATE VIEW v_mon_catalogue
WITH (security_invoker = on) AS
SELECT
  p.id AS produit_id,
  p.nom,
  p.reference,
  p.image_url,
  p.disponible,
  p.created_at,
  c.nom AS categorie,
  (SELECT count(*) FROM stocks s WHERE s.produit_id = p.id) AS boutiques_suivant,
  (SELECT count(*) FROM ruptures r
    WHERE r.produit_id = p.id AND r.statut = 'signalee'
      AND r.confirmee_le IS NOT NULL) AS ruptures_ouvertes,
  (SELECT count(*) FROM ruptures r WHERE r.produit_id = p.id) AS signalements_total
FROM produits p
LEFT JOIN categories_produit c ON c.id = p.categorie_id
WHERE p.fabricant_id = auth_id_metier() AND auth_role() = 'fabricant';

COMMENT ON VIEW v_mon_catalogue IS
  'Le catalogue du fabricant appelant, avec ce que chaque référence produit sur le réseau. Le filtre est dans la vue ET dans les politiques : la vue rend l''écran simple, les politiques protègent.';

-- ── 4. Les ruptures de son catalogue, avec le détail ────────────────────────
--
-- La maquette Fabricant montre le produit signalé avec sa photo, sa référence,
-- la quantité demandée et la boutique. `v_ruptures_ouvertes` existait déjà mais
-- ne portait pas la commune, sur laquelle la maquette propose de filtrer.

CREATE VIEW v_mes_ruptures
WITH (security_invoker = on) AS
SELECT
  r.id AS rupture_id,
  r.statut,
  r.quantite_demandee,
  r.signalement_automatique,
  r.date_signalement,
  r.confirmee_le,
  r.date_resolution,
  EXTRACT(EPOCH FROM (now() - COALESCE(r.confirmee_le, r.date_signalement)))::INTEGER
    AS attente_secondes,
  p.id   AS produit_id,
  p.nom  AS produit,
  p.reference,
  p.image_url,
  c.nom  AS categorie,
  pdv.nom     AS point_de_vente,
  pdv.commune,
  d.nom  AS distributeur
FROM ruptures r
JOIN produits p           ON p.id = r.produit_id
LEFT JOIN categories_produit c ON c.id = p.categorie_id
JOIN points_de_vente pdv  ON pdv.id = r.point_de_vente_id
LEFT JOIN distributeurs d ON d.id = r.distributeur_id
WHERE p.fabricant_id = auth_id_metier() AND auth_role() = 'fabricant';

COMMENT ON VIEW v_mes_ruptures IS
  'Les ruptures portant sur le catalogue du fabricant appelant, et sur aucun autre. Celles d''un concurrent ne lui sont jamais transmises.';
