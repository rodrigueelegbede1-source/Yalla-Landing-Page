CREATE TABLE demandes_catalogue_pdf (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  fabricant_id UUID NOT NULL REFERENCES fabricants(id) ON DELETE CASCADE,
  auteur_utilisateur_id UUID NOT NULL REFERENCES utilisateurs(id) ON DELETE RESTRICT,
  fichier_pdf TEXT NOT NULL,
  statut TEXT NOT NULL DEFAULT 'en_attente'
    CHECK (statut IN ('en_attente', 'en_cours', 'traitee', 'refusee')),
  traite_par UUID REFERENCES utilisateurs(id) ON DELETE SET NULL,
  traite_le TIMESTAMPTZ,
  note_traitement TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (fichier_pdf ~* '\.pdf$')
);

CREATE INDEX idx_demandes_catalogue_pdf_statut
  ON demandes_catalogue_pdf(statut, created_at DESC);

ALTER TABLE demandes_catalogue_pdf ENABLE ROW LEVEL SECURITY;

CREATE POLICY demandes_catalogue_pdf_lecture ON demandes_catalogue_pdf
FOR SELECT TO authenticated
USING (est_admin() OR auteur_utilisateur_id = auth_utilisateur_id());

GRANT SELECT ON demandes_catalogue_pdf TO authenticated;

CREATE OR REPLACE FUNCTION soumettre_catalogue_pdf(
  p_fabricant_id UUID,
  p_fichier_pdf TEXT
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_auteur UUID := auth_utilisateur_id();
  v_id UUID;
BEGIN
  IF v_auteur IS NULL OR NOT peut_gerer_catalogue(p_fabricant_id) THEN
    RAISE EXCEPTION 'Vous ne pouvez pas transmettre ce catalogue'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_fichier_pdf IS NULL
     OR p_fichier_pdf NOT LIKE v_auteur::TEXT || '/catalogues-pdf/%'
     OR p_fichier_pdf !~* '\.pdf$'
     OR NOT EXISTS (
       SELECT 1 FROM storage.objects
        WHERE bucket_id = 'catalogue-imports' AND name = p_fichier_pdf
     ) THEN
    RAISE EXCEPTION 'Le PDF doit être présent dans votre espace privé'
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO demandes_catalogue_pdf (
    fabricant_id, auteur_utilisateur_id, fichier_pdf
  ) VALUES (
    p_fabricant_id, v_auteur, p_fichier_pdf
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION soumettre_catalogue_pdf(UUID, TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION soumettre_catalogue_pdf(UUID, TEXT)
  TO authenticated;

CREATE OR REPLACE FUNCTION changer_statut_demande_catalogue_pdf(
  p_demande_id UUID,
  p_statut TEXT,
  p_note TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_lignes INTEGER;
BEGIN
  IF NOT est_admin() THEN
    RAISE EXCEPTION 'Seul l’administrateur peut traiter cette demande'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_statut NOT IN ('en_cours', 'traitee', 'refusee') THEN
    RAISE EXCEPTION 'Statut de traitement invalide'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE demandes_catalogue_pdf
     SET statut = p_statut,
         traite_par = auth_utilisateur_id(),
         traite_le = CASE WHEN p_statut IN ('traitee', 'refusee') THEN now() ELSE NULL END,
         note_traitement = NULLIF(btrim(COALESCE(p_note, '')), '')
   WHERE id = p_demande_id
     AND statut IN ('en_attente', 'en_cours');
  GET DIAGNOSTICS v_lignes = ROW_COUNT;
  RETURN v_lignes = 1;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION changer_statut_demande_catalogue_pdf(UUID, TEXT, TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION changer_statut_demande_catalogue_pdf(UUID, TEXT, TEXT)
  TO authenticated;