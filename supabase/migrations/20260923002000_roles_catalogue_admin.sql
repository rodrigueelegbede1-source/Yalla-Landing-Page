-- Rôles mobiles, gestion admin et droits catalogue.

-- Le compte fabricant doit pouvoir être créé par l'admin ou l'agent, puis
-- utiliser le même flux Edge que les autres rôles.
CREATE OR REPLACE FUNCTION creer_compte_metier(
  p_auth_user_id UUID,
  p_nom          TEXT,
  p_telephone    TEXT,
  p_role         role_utilisateur,
  p_details      JSONB DEFAULT '{}'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_createur role_utilisateur := auth_role();
  v_createur_metier UUID := auth_id_metier();
  v_tel TEXT := normaliser_telephone(p_telephone);
  v_u_id UUID;
  v_id_metier UUID;
BEGIN
  IF v_createur IS NULL OR v_createur NOT IN ('administrateur', 'agent_recenseur', 'distributeur') THEN
    RAISE EXCEPTION 'Authentification ou rôle créateur invalide' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT (v_createur = 'administrateur'
       OR (v_createur = 'agent_recenseur' AND p_role IN ('point_de_vente', 'distributeur', 'fabricant'))
       OR (v_createur = 'distributeur' AND p_role = 'livreur')) THEN
    RAISE EXCEPTION 'Votre rôle ne permet pas de créer ce compte' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_tel IS NULL OR length(v_tel) <> 13 OR left(v_tel, 3) <> '225' THEN
    RAISE EXCEPTION 'Numéro de téléphone invalide' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM utilisateurs WHERE telephone = v_tel) THEN
    RAISE EXCEPTION 'Ce numéro est déjà rattaché à un compte Yalla' USING ERRCODE = 'unique_violation';
  END IF;

  INSERT INTO utilisateurs (nom, telephone, role, auth_user_id)
  VALUES (trim(p_nom), v_tel, p_role, p_auth_user_id)
  RETURNING id INTO v_u_id;

  IF p_role = 'fabricant' THEN
    INSERT INTO fabricants (utilisateur_id, nom)
    VALUES (v_u_id, COALESCE(NULLIF(trim(p_details->>'nom_societe'), ''), trim(p_nom)))
    RETURNING id INTO v_id_metier;
  ELSIF p_role = 'point_de_vente' THEN
    INSERT INTO points_de_vente (nom, type_activite, commune, ville, adresse, position,
      gerant_nom, telephone, statut, agent_recenseur_id, utilisateur_id)
    VALUES (trim(p_details->>'nom_boutique'), (p_details->>'type_activite')::type_activite,
      trim(p_details->>'commune'), COALESCE(NULLIF(trim(p_details->>'ville'), ''), 'Abidjan'),
      NULLIF(trim(COALESCE(p_details->>'adresse', '')), ''),
      ST_SetSRID(ST_MakePoint((p_details->>'longitude')::DOUBLE PRECISION,
        (p_details->>'latitude')::DOUBLE PRECISION), 4326)::GEOGRAPHY,
      trim(p_nom), v_tel, 'actif',
      CASE WHEN v_createur = 'agent_recenseur' THEN v_createur_metier ELSE NULL END, v_u_id)
    RETURNING id INTO v_id_metier;
  ELSIF p_role = 'distributeur' THEN
    INSERT INTO distributeurs (nom, telephone, utilisateur_id, fabricant_id, statut)
    VALUES (COALESCE(NULLIF(trim(p_details->>'nom_societe'), ''), trim(p_nom)), v_tel,
      v_u_id, NULLIF(p_details->>'fabricant_id', '')::UUID, 'actif')
    RETURNING id INTO v_id_metier;
  ELSIF p_role = 'livreur' THEN
    INSERT INTO livreurs (utilisateur_id, distributeur_id)
    VALUES (v_u_id, v_createur_metier)
    RETURNING id INTO v_id_metier;
  ELSIF p_role = 'agent_recenseur' THEN
    INSERT INTO agents_recenseurs (utilisateur_id, secteur)
    VALUES (v_u_id, COALESCE(NULLIF(trim(p_details->>'secteur'), ''), 'Abidjan'))
    RETURNING id INTO v_id_metier;
  END IF;

  RETURN jsonb_build_object('utilisateur_id', v_u_id, 'id_metier', v_id_metier,
    'telephone', v_tel, 'role', p_role);
END;
$fn$;

-- Un accord explicite permet à un fabricant de déléguer son catalogue à un
-- distributeur affilié ou indépendant. L'admin peut aussi l'initialiser.
CREATE TABLE IF NOT EXISTS autorisations_catalogue (
  fabricant_id UUID NOT NULL REFERENCES fabricants(id) ON DELETE CASCADE,
  distributeur_id UUID NOT NULL REFERENCES distributeurs(id) ON DELETE CASCADE,
  accorde_par UUID NOT NULL REFERENCES utilisateurs(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (fabricant_id, distributeur_id)
);
ALTER TABLE autorisations_catalogue ENABLE ROW LEVEL SECURITY;
CREATE POLICY autorisations_catalogue_admin ON autorisations_catalogue FOR ALL TO authenticated
  USING (est_admin()) WITH CHECK (est_admin());
CREATE POLICY autorisations_catalogue_fabricant ON autorisations_catalogue FOR SELECT TO authenticated
  USING (fabricant_id = auth_id_metier() AND auth_role() = 'fabricant');
CREATE POLICY autorisations_catalogue_distributeur ON autorisations_catalogue FOR SELECT TO authenticated
  USING (distributeur_id = auth_id_metier() AND auth_role() = 'distributeur');

CREATE OR REPLACE FUNCTION autoriser_catalogue(
  p_fabricant_id UUID, p_distributeur_id UUID
)
RETURNS autorisations_catalogue
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_ligne autorisations_catalogue;
BEGIN
  IF NOT (est_admin() OR (auth_role() = 'fabricant' AND auth_id_metier() = p_fabricant_id)) THEN
    RAISE EXCEPTION 'Seul le fabricant ou l''administrateur peut accorder ce catalogue'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO autorisations_catalogue (fabricant_id, distributeur_id, accorde_par)
  VALUES (p_fabricant_id, p_distributeur_id, auth_utilisateur_id())
  ON CONFLICT (fabricant_id, distributeur_id) DO UPDATE SET accorde_par = EXCLUDED.accorde_par
  RETURNING * INTO v_ligne;
  RETURN v_ligne;
END;
$fn$;
REVOKE EXECUTE ON FUNCTION autoriser_catalogue FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION autoriser_catalogue TO authenticated;

-- Le distributeur peut créer un produit uniquement si le fabricant l'a autorisé.
DROP FUNCTION IF EXISTS enregistrer_produit(TEXT, TEXT, TEXT, UUID, BOOLEAN);

CREATE OR REPLACE FUNCTION enregistrer_produit(
  p_nom TEXT, p_categorie TEXT DEFAULT NULL, p_reference TEXT DEFAULT NULL,
  p_produit_id UUID DEFAULT NULL, p_disponible BOOLEAN DEFAULT true,
  p_fabricant_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_fabricant UUID := COALESCE(p_fabricant_id, auth_id_metier());
  v_nom TEXT := trim(COALESCE(p_nom, ''));
  v_cat TEXT := NULLIF(trim(COALESCE(p_categorie, '')), '');
  v_ref TEXT := NULLIF(upper(trim(COALESCE(p_reference, ''))), '');
  v_cat_id UUID; v_id UUID; v_compteur INTEGER := 0;
BEGIN
  IF auth_role() = 'fabricant' AND v_fabricant <> auth_id_metier() THEN
    RAISE EXCEPTION 'Catalogue fabricant interdit' USING ERRCODE = 'insufficient_privilege';
  ELSIF auth_role() = 'distributeur' AND NOT EXISTS (
    SELECT 1 FROM distributeurs d
    WHERE d.id = auth_id_metier() AND d.fabricant_id = v_fabricant
    UNION ALL
    SELECT 1 FROM autorisations_catalogue
    WHERE fabricant_id = v_fabricant AND distributeur_id = auth_id_metier()
  ) THEN
    RAISE EXCEPTION 'Accord fabricant absent pour ce catalogue' USING ERRCODE = 'insufficient_privilege';
  ELSIF auth_role() NOT IN ('fabricant', 'distributeur') THEN
    RAISE EXCEPTION 'Réservé au fabricant ou au distributeur autorisé' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(v_nom) < 2 OR v_fabricant IS NULL THEN
    RAISE EXCEPTION 'Nom du produit ou fabricant manquant' USING ERRCODE = 'check_violation';
  END IF;
  IF v_cat IS NOT NULL THEN
    SELECT id INTO v_cat_id FROM categories_produit WHERE lower(nom) = lower(v_cat) LIMIT 1;
    IF v_cat_id IS NULL THEN INSERT INTO categories_produit(nom) VALUES(v_cat) RETURNING id INTO v_cat_id; END IF;
  END IF;
  IF p_produit_id IS NOT NULL THEN
    UPDATE produits SET nom=v_nom, categorie_id=COALESCE(v_cat_id,categorie_id), disponible=p_disponible
    WHERE id=p_produit_id AND fabricant_id=v_fabricant RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Produit introuvable dans le catalogue' USING ERRCODE='no_data_found'; END IF;
  ELSE
    IF v_ref IS NULL THEN
      v_ref := upper(substring(regexp_replace(v_nom, '[^A-Za-z0-9]', '', 'g') from 1 for 8));
      WHILE EXISTS (SELECT 1 FROM produits WHERE fabricant_id=v_fabricant AND reference=v_ref) LOOP
        v_compteur := v_compteur + 1; v_ref := v_ref || '-' || v_compteur;
      END LOOP;
    END IF;
    INSERT INTO produits(fabricant_id,nom,reference,categorie_id,disponible)
    VALUES(v_fabricant,v_nom,v_ref,v_cat_id,p_disponible) RETURNING id INTO v_id;
  END IF;
  RETURN jsonb_build_object('produit_id',v_id,'reference',v_ref,'cree',p_produit_id IS NULL);
END;
$fn$;
REVOKE EXECUTE ON FUNCTION enregistrer_produit FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION enregistrer_produit TO authenticated;

-- Tous les catalogues disponibles dès qu'une boutique est active.
DROP VIEW IF EXISTS v_catalogue_point_de_vente;
CREATE VIEW v_catalogue_point_de_vente WITH (security_invoker = on) AS
SELECT pdv.id AS point_de_vente_id, p.id AS produit_id, p.nom AS produit_nom,
  p.reference, p.image_url, f.id AS fabricant_id, f.nom AS fabricant_nom,
  c.nom AS categorie_nom, s.quantite AS quantite_en_stock,
  EXISTS (SELECT 1 FROM ruptures r WHERE r.produit_id=p.id AND r.point_de_vente_id=pdv.id
    AND r.statut IN ('signalee','prise_en_charge')) AS deja_demande
FROM points_de_vente pdv CROSS JOIN produits p
JOIN fabricants f ON f.id=p.fabricant_id
LEFT JOIN categories_produit c ON c.id=p.categorie_id
LEFT JOIN stocks s ON s.produit_id=p.id AND s.point_de_vente_id=pdv.id
WHERE pdv.id=auth_id_metier() AND auth_role()='point_de_vente' AND pdv.statut='actif' AND p.disponible;

CREATE POLICY produits_catalogue_auth ON produits FOR SELECT TO authenticated USING (disponible = true);

CREATE OR REPLACE VIEW v_stock_point_de_vente
WITH (security_invoker = on) AS
SELECT
  s.point_de_vente_id, s.produit_id,
  COALESCE(p.nom, s.produit_libre_nom) AS produit_nom,
  p.reference, p.image_url, f.nom AS fabricant_nom, c.nom AS categorie_nom,
  s.quantite, s.date_maj, (s.quantite <= 0) AS rupture_ouverte
FROM stocks s
LEFT JOIN produits p ON p.id = s.produit_id
LEFT JOIN fabricants f ON f.id = p.fabricant_id
LEFT JOIN categories_produit c ON c.id = p.categorie_id;

-- L'admin retire un acteur sans détruire son historique.
CREATE OR REPLACE FUNCTION retirer_acteur(p_role TEXT, p_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $fn$
DECLARE v_nb INTEGER;
BEGIN
  IF NOT est_admin() THEN RAISE EXCEPTION 'Réservé à l''administrateur' USING ERRCODE='insufficient_privilege'; END IF;
  IF p_role='fabricant' THEN UPDATE fabricants SET statut='suspendu' WHERE id=p_id; GET DIAGNOSTICS v_nb=ROW_COUNT;
  ELSIF p_role='distributeur' THEN UPDATE distributeurs SET statut='suspendu' WHERE id=p_id; GET DIAGNOSTICS v_nb=ROW_COUNT;
  ELSIF p_role='point_de_vente' THEN UPDATE points_de_vente SET statut='retire' WHERE id=p_id; GET DIAGNOSTICS v_nb=ROW_COUNT;
  ELSIF p_role='agent_recenseur' THEN UPDATE agents_recenseurs SET secteur='Retiré' WHERE id=p_id; GET DIAGNOSTICS v_nb=ROW_COUNT;
  ELSE RAISE EXCEPTION 'Rôle non retirable';
  END IF;
  RETURN v_nb > 0;
END;
$fn$;
REVOKE EXECUTE ON FUNCTION retirer_acteur FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION retirer_acteur TO authenticated;

CREATE VIEW v_acteurs_admin WITH (security_invoker=on) AS
SELECT u.id AS utilisateur_id,u.nom,u.telephone,u.role::text AS role,
  COALESCE(f.id,d.id,p.id,a.id) AS id_metier,
  CASE WHEN f.id IS NOT NULL THEN f.nom WHEN d.id IS NOT NULL THEN d.nom WHEN p.id IS NOT NULL THEN p.nom ELSE u.nom END AS libelle,
  COALESCE(f.statut::text,d.statut::text,p.statut::text,'actif') AS statut
FROM utilisateurs u LEFT JOIN fabricants f ON f.utilisateur_id=u.id
LEFT JOIN distributeurs d ON d.utilisateur_id=u.id LEFT JOIN points_de_vente p ON p.utilisateur_id=u.id
LEFT JOIN agents_recenseurs a ON a.utilisateur_id=u.id
WHERE est_admin();
