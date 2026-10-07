-- Catalogue détaillé avec images obligatoires et imports tracés.

ALTER TABLE produits
  ADD COLUMN description TEXT,
  ADD COLUMN format TEXT,
  ADD COLUMN caracteristiques JSONB NOT NULL DEFAULT '{}'::JSONB;

ALTER TABLE produits
  ADD CONSTRAINT produits_image_requise_si_disponible
  CHECK (NOT disponible OR NULLIF(btrim(image_url), '') IS NOT NULL)
  NOT VALID;

COMMENT ON COLUMN produits.description IS
  'Description destinée à la sélection du produit par le revendeur.';
COMMENT ON COLUMN produits.format IS
  'Contenance ou format commercial affiché dans le catalogue.';
COMMENT ON COLUMN produits.caracteristiques IS
  'Caractéristiques descriptives libres, sous forme JSON objet clé/valeur.';

CREATE OR REPLACE FUNCTION peut_gerer_catalogue(p_fabricant_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_role TEXT := auth_role();
  v_id UUID := auth_id_metier();
BEGIN
  IF p_fabricant_id IS NULL THEN RETURN false; END IF;
  IF v_role = 'administrateur' THEN
    RETURN EXISTS (SELECT 1 FROM fabricants WHERE id = p_fabricant_id);
  ELSIF v_role = 'fabricant' THEN
    RETURN v_id = p_fabricant_id;
  ELSIF v_role = 'distributeur' THEN
    RETURN EXISTS (
      SELECT 1 FROM distributeurs d
       WHERE d.id = v_id AND d.statut = 'actif'
         AND (
           d.fabricant_id = p_fabricant_id
           OR EXISTS (
             SELECT 1 FROM attributions_reseau ar
              WHERE ar.distributeur_id = d.id
                AND ar.fabricant_id = p_fabricant_id
           )
         )
    );
  END IF;
  RETURN false;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION peut_gerer_catalogue(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION peut_gerer_catalogue(UUID) TO authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'catalogue', 'catalogue', true, 20971520,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE
SET public = true,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'catalogue-imports', 'catalogue-imports', false, 52428800,
  ARRAY[
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-excel', 'text/csv', 'application/csv',
    'application/zip', 'application/x-zip-compressed', 'application/pdf'
  ]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE POLICY catalogue_media_insert ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'catalogue'
  AND auth_role() IN ('administrateur', 'fabricant', 'distributeur')
  AND (storage.foldername(name))[1] = auth_utilisateur_id()::TEXT
);

CREATE POLICY catalogue_media_update ON storage.objects
FOR UPDATE TO authenticated
USING (
  bucket_id = 'catalogue'
  AND (storage.foldername(name))[1] = auth_utilisateur_id()::TEXT
  AND auth_role() IN ('administrateur', 'fabricant', 'distributeur')
)
WITH CHECK (
  bucket_id = 'catalogue'
  AND (storage.foldername(name))[1] = auth_utilisateur_id()::TEXT
  AND auth_role() IN ('administrateur', 'fabricant', 'distributeur')
);

CREATE POLICY catalogue_media_delete ON storage.objects
FOR DELETE TO authenticated
USING (
  bucket_id = 'catalogue'
  AND (storage.foldername(name))[1] = auth_utilisateur_id()::TEXT
  AND auth_role() IN ('administrateur', 'fabricant', 'distributeur')
);

CREATE POLICY catalogue_imports_insert ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'catalogue-imports'
  AND (storage.foldername(name))[1] = auth_utilisateur_id()::TEXT
  AND auth_role() IN ('administrateur', 'fabricant', 'distributeur')
);

CREATE POLICY catalogue_imports_read ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'catalogue-imports'
  AND (est_admin() OR (storage.foldername(name))[1] = auth_utilisateur_id()::TEXT)
);

CREATE POLICY catalogue_imports_delete ON storage.objects
FOR DELETE TO authenticated
USING (
  bucket_id = 'catalogue-imports'
  AND (est_admin() OR (storage.foldername(name))[1] = auth_utilisateur_id()::TEXT)
);

CREATE TABLE imports_catalogue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  fabricant_id UUID NOT NULL REFERENCES fabricants(id) ON DELETE CASCADE,
  auteur_utilisateur_id UUID NOT NULL REFERENCES utilisateurs(id) ON DELETE RESTRICT,
  fichier_tableur TEXT NOT NULL,
  document_pdf_url TEXT,
  produits_importes INTEGER NOT NULL CHECK (produits_importes > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE imports_catalogue ENABLE ROW LEVEL SECURITY;

CREATE POLICY imports_catalogue_lecture ON imports_catalogue
FOR SELECT TO authenticated
USING (est_admin() OR auteur_utilisateur_id = auth_utilisateur_id());

GRANT SELECT ON imports_catalogue TO authenticated;

CREATE OR REPLACE FUNCTION importer_catalogue(
  p_fabricant_id UUID,
  p_lignes JSONB,
  p_fichier_tableur TEXT,
  p_document_pdf_url TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_ligne JSONB;
  v_nom TEXT;
  v_reference TEXT;
  v_categorie TEXT;
  v_categorie_id UUID;
  v_image_url TEXT;
  v_description TEXT;
  v_format TEXT;
  v_caracteristiques JSONB;
  v_compteur INTEGER := 0;
  v_import_id UUID;
  v_dossier TEXT := auth_utilisateur_id()::TEXT || '/';
  v_prefixe TEXT := '/storage/v1/object/public/catalogue/';
  v_chemin TEXT;
BEGIN
  IF NOT peut_gerer_catalogue(p_fabricant_id) THEN
    RAISE EXCEPTION 'Vous ne pouvez pas gérer le catalogue de cette marque'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF jsonb_typeof(p_lignes) <> 'array'
     OR jsonb_array_length(p_lignes) = 0
     OR jsonb_array_length(p_lignes) > 500 THEN
    RAISE EXCEPTION 'Le fichier doit contenir entre 1 et 500 produits'
      USING ERRCODE = 'check_violation';
  END IF;
  IF NULLIF(btrim(p_fichier_tableur), '') IS NULL
     OR p_fichier_tableur NOT LIKE v_dossier || '%' THEN
    RAISE EXCEPTION 'Le tableur source doit provenir de votre espace privé'
      USING ERRCODE = 'check_violation';
  END IF;
  v_chemin := p_fichier_tableur;
  IF NOT EXISTS (
    SELECT 1 FROM storage.objects
     WHERE bucket_id = 'catalogue-imports' AND name = v_chemin
  ) THEN
    RAISE EXCEPTION 'Le tableur source est introuvable dans votre espace privé'
      USING ERRCODE = 'check_violation';
  END IF;
  IF p_document_pdf_url IS NOT NULL
     AND p_document_pdf_url NOT LIKE v_dossier || '%' THEN
    RAISE EXCEPTION 'Le document PDF doit provenir de votre espace privé'
      USING ERRCODE = 'check_violation';
  END IF;
  IF p_document_pdf_url IS NOT NULL THEN
    v_chemin := p_document_pdf_url;
    IF NOT EXISTS (
      SELECT 1 FROM storage.objects
       WHERE bucket_id = 'catalogue-imports' AND name = v_chemin
    ) THEN
      RAISE EXCEPTION 'Le PDF source est introuvable dans votre espace privé'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1
      FROM jsonb_array_elements(p_lignes) AS ligne(value)
     GROUP BY upper(btrim(value->>'reference'))
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Le fichier contient des références dupliquées'
      USING ERRCODE = 'unique_violation';
  END IF;

  FOR v_ligne IN SELECT value FROM jsonb_array_elements(p_lignes)
  LOOP
    v_nom := NULLIF(btrim(v_ligne->>'nom'), '');
    v_reference := upper(NULLIF(btrim(v_ligne->>'reference'), ''));
    v_categorie := NULLIF(btrim(v_ligne->>'categorie'), '');
    v_image_url := NULLIF(btrim(v_ligne->>'image_url'), '');
    v_description := NULLIF(btrim(v_ligne->>'description'), '');
    v_format := NULLIF(btrim(v_ligne->>'format'), '');
    v_caracteristiques := COALESCE(v_ligne->'caracteristiques', '{}'::JSONB);

    IF length(COALESCE(v_nom, '')) < 2 OR v_reference IS NULL THEN
      RAISE EXCEPTION 'Chaque ligne doit avoir un nom et une référence produit'
        USING ERRCODE = 'check_violation';
    END IF;
     IF v_image_url IS NULL
       OR position(v_prefixe || v_dossier in v_image_url) = 0 THEN
      RAISE EXCEPTION 'Une image du stockage Yalla manque pour la référence %', v_reference
        USING ERRCODE = 'check_violation';
    END IF;
    v_chemin := split_part(v_image_url, v_prefixe, 2);
    IF NOT EXISTS (
      SELECT 1 FROM storage.objects
       WHERE bucket_id = 'catalogue' AND name = v_chemin
    ) THEN
      RAISE EXCEPTION 'Le fichier image de % est introuvable dans votre stockage', v_reference
        USING ERRCODE = 'check_violation';
    END IF;
    IF jsonb_typeof(v_caracteristiques) <> 'object' THEN
      RAISE EXCEPTION 'Les caractéristiques de % doivent être un objet clé/valeur', v_reference
        USING ERRCODE = 'check_violation';
    END IF;

    v_categorie_id := NULL;
    IF v_categorie IS NOT NULL THEN
      SELECT id INTO v_categorie_id FROM categories_produit
       WHERE lower(nom) = lower(v_categorie) LIMIT 1;
      IF v_categorie_id IS NULL THEN
        INSERT INTO categories_produit(nom) VALUES (v_categorie)
        RETURNING id INTO v_categorie_id;
      END IF;
    END IF;

    IF auth_role() = 'distributeur' AND EXISTS (
      SELECT 1 FROM produits
       WHERE fabricant_id = p_fabricant_id AND reference = v_reference
    ) THEN
      RAISE EXCEPTION 'La référence % existe déjà; seul le fabricant peut la modifier', v_reference
        USING ERRCODE = 'unique_violation';
    END IF;

    INSERT INTO produits (
      fabricant_id, nom, reference, categorie_id, image_url,
      description, format, caracteristiques, disponible
    ) VALUES (
      p_fabricant_id, v_nom, v_reference, v_categorie_id, v_image_url,
      v_description, v_format, v_caracteristiques, true
    )
    ON CONFLICT (fabricant_id, reference) DO UPDATE SET
      nom = EXCLUDED.nom,
      categorie_id = EXCLUDED.categorie_id,
      image_url = EXCLUDED.image_url,
      description = EXCLUDED.description,
      format = EXCLUDED.format,
      caracteristiques = EXCLUDED.caracteristiques,
      disponible = true;

    v_compteur := v_compteur + 1;
  END LOOP;

  INSERT INTO imports_catalogue (
    fabricant_id, auteur_utilisateur_id, fichier_tableur,
    document_pdf_url, produits_importes
  ) VALUES (
    p_fabricant_id, auth_utilisateur_id(), btrim(p_fichier_tableur),
    NULLIF(btrim(COALESCE(p_document_pdf_url, '')), ''), v_compteur
  ) RETURNING id INTO v_import_id;

  RETURN jsonb_build_object(
    'import_id', v_import_id,
    'fabricant_id', p_fabricant_id,
    'produits_importes', v_compteur
  );
END;
$fn$;

REVOKE EXECUTE ON FUNCTION importer_catalogue(UUID, JSONB, TEXT, TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION importer_catalogue(UUID, JSONB, TEXT, TEXT)
  TO authenticated;

CREATE OR REPLACE VIEW v_catalogue_point_de_vente
WITH (security_invoker = on) AS
SELECT
  pdv.id AS point_de_vente_id,
  p.id AS produit_id,
  p.nom AS produit_nom,
  p.reference,
  p.image_url,
  f.id AS fabricant_id,
  f.nom AS fabricant_nom,
  c.nom AS categorie_nom,
  s.quantite AS quantite_en_stock,
  EXISTS (
    SELECT 1 FROM ruptures r
     WHERE r.produit_id = p.id
       AND r.point_de_vente_id = pdv.id
       AND r.statut IN ('signalee', 'prise_en_charge')
  ) AS deja_demande,
  p.description,
  p.format,
  p.caracteristiques
FROM points_de_vente pdv
CROSS JOIN produits p
JOIN fabricants f ON f.id = p.fabricant_id
LEFT JOIN categories_produit c ON c.id = p.categorie_id
LEFT JOIN stocks s ON s.produit_id = p.id AND s.point_de_vente_id = pdv.id
WHERE pdv.id = auth_id_metier()
  AND auth_role() = 'point_de_vente'
  AND pdv.statut = 'actif'
  AND p.disponible
  AND NULLIF(btrim(p.image_url), '') IS NOT NULL;

CREATE OR REPLACE VIEW v_mon_catalogue
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
  (SELECT count(*) FROM ruptures r WHERE r.produit_id = p.id) AS signalements_total,
  p.description,
  p.format,
  p.caracteristiques
FROM produits p
LEFT JOIN categories_produit c ON c.id = p.categorie_id
WHERE p.fabricant_id = auth_id_metier() AND auth_role() = 'fabricant';

COMMENT ON VIEW v_catalogue_point_de_vente IS
  'Catalogue boutique : seules les références disponibles avec image sont proposées. Les références historiques sans photo restent visibles au fabricant pour réparation.';