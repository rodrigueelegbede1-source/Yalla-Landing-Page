-- Communications commerciales et notes d'information soumises à validation.

ALTER TABLE notifications
  ADD COLUMN statut_validation TEXT NOT NULL DEFAULT 'publiee'
    CHECK (statut_validation IN ('en_attente', 'publiee', 'refusee')),
  ADD COLUMN cree_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN fabricant_id UUID REFERENCES fabricants(id) ON DELETE CASCADE,
  ADD COLUMN distributeur_id UUID REFERENCES distributeurs(id) ON DELETE CASCADE,
  ADD COLUMN valide_par UUID REFERENCES utilisateurs(id) ON DELETE SET NULL,
  ADD COLUMN motif_refus TEXT;

CREATE INDEX idx_notifications_validation
  ON notifications(statut_validation, cree_le DESC);

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'notifications-brouillons', 'notifications-brouillons', false, 5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY notifications_destinataire ON notifications;
CREATE POLICY notifications_destinataire ON notifications FOR SELECT TO authenticated
  USING (
    statut_validation = 'publiee'
    AND (
      cible = 'reseau_complet'
      OR (cible = 'points_de_vente' AND auth_role() = 'point_de_vente')
      OR (cible = 'distributeurs' AND auth_role() = 'distributeur')
      OR (cible = 'fabricants' AND auth_role() = 'fabricant')
      OR (cible = 'livreurs' AND auth_role() = 'livreur')
    )
    AND (
      commune IS NULL
      OR commune = commune_du_point_de_vente_courant()
    )
    AND (
      fabricant_id IS NULL
      OR (
        auth_role() = 'point_de_vente'
        AND EXISTS (
          SELECT 1 FROM attributions_reseau ar
           WHERE ar.point_de_vente_id = auth_id_metier()
             AND ar.fabricant_id = notifications.fabricant_id
        )
      )
    )
    AND (
      distributeur_id IS NULL
      OR (
        auth_role() = 'point_de_vente'
        AND EXISTS (
          SELECT 1 FROM attributions_reseau ar
           WHERE ar.point_de_vente_id = auth_id_metier()
             AND ar.distributeur_id = notifications.distributeur_id
        )
      )
    )
  );

DROP POLICY IF EXISTS notifications_visuels_admin_insert ON storage.objects;
CREATE POLICY notifications_visuels_admin_insert ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'notifications' AND public.est_admin());

DROP POLICY IF EXISTS notifications_visuels_admin_update ON storage.objects;
CREATE POLICY notifications_visuels_admin_update ON storage.objects
FOR UPDATE TO authenticated
USING (bucket_id = 'notifications' AND public.est_admin())
WITH CHECK (bucket_id = 'notifications' AND public.est_admin());

DROP POLICY IF EXISTS notifications_visuels_admin_delete ON storage.objects;
CREATE POLICY notifications_visuels_admin_delete ON storage.objects
FOR DELETE TO authenticated
USING (bucket_id = 'notifications' AND public.est_admin());

CREATE POLICY notifications_brouillons_insert ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'notifications-brouillons'
  AND auth_role() IN ('administrateur', 'fabricant', 'distributeur')
  AND (storage.foldername(name))[1] = auth_utilisateur_id()::TEXT
);

CREATE POLICY notifications_brouillons_update ON storage.objects
FOR UPDATE TO authenticated
USING (
  bucket_id = 'notifications-brouillons'
  AND public.est_admin()
)
WITH CHECK (
  bucket_id = 'notifications-brouillons'
  AND public.est_admin()
);

CREATE POLICY notifications_brouillons_delete ON storage.objects
FOR DELETE TO authenticated
USING (
  bucket_id = 'notifications-brouillons'
  AND (
    public.est_admin()
    OR (
      (storage.foldername(name))[1] = auth_utilisateur_id()::TEXT
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n WHERE n.visuel_url = storage.objects.name
      )
    )
  )
);

CREATE POLICY notifications_brouillons_read ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'notifications-brouillons'
  AND (
    public.est_admin()
    OR (storage.foldername(name))[1] = auth_utilisateur_id()::TEXT
    OR EXISTS (
      SELECT 1 FROM public.notifications n
       WHERE n.visuel_url = storage.objects.name
         AND n.statut_validation = 'publiee'
         AND (
           n.cible = 'reseau_complet'
           OR (n.cible = 'points_de_vente' AND public.auth_role() = 'point_de_vente')
           OR (n.cible = 'distributeurs' AND public.auth_role() = 'distributeur')
           OR (n.cible = 'fabricants' AND public.auth_role() = 'fabricant')
           OR (n.cible = 'livreurs' AND public.auth_role() = 'livreur')
         )
         AND (n.commune IS NULL OR n.commune = public.commune_du_point_de_vente_courant())
         AND (
           n.fabricant_id IS NULL
           OR EXISTS (
             SELECT 1 FROM public.attributions_reseau ar
              WHERE ar.point_de_vente_id = public.auth_id_metier()
                AND ar.fabricant_id = n.fabricant_id
           )
         )
         AND (
           n.distributeur_id IS NULL
           OR EXISTS (
             SELECT 1 FROM public.attributions_reseau ar
              WHERE ar.point_de_vente_id = public.auth_id_metier()
                AND ar.distributeur_id = n.distributeur_id
           )
         )
    )
  )
);

CREATE OR REPLACE FUNCTION soumettre_communication(
  p_type TEXT,
  p_titre TEXT,
  p_message TEXT,
  p_commune TEXT DEFAULT NULL,
  p_visuel_url TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_role TEXT := auth_role();
  v_auteur UUID := auth_utilisateur_id();
  v_id_metier UUID := auth_id_metier();
  v_fabricant_id UUID;
  v_distributeur_id UUID;
  v_commune TEXT := NULLIF(btrim(COALESCE(p_commune, '')), '');
  v_visuel TEXT := NULLIF(btrim(COALESCE(p_visuel_url, '')), '');
  v_dossier TEXT := v_auteur::TEXT || '/communications/';
BEGIN
  IF v_role NOT IN ('fabricant', 'distributeur') OR v_auteur IS NULL OR v_id_metier IS NULL THEN
    RAISE EXCEPTION 'Seuls les fabricants et distributeurs peuvent soumettre une communication'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_type NOT IN ('notification', 'splash_publicitaire') THEN
    RAISE EXCEPTION 'Seules les notes et publicités sont soumises à validation'
      USING ERRCODE = 'check_violation';
  END IF;
  IF length(btrim(COALESCE(p_titre, ''))) < 3
     OR length(btrim(COALESCE(p_titre, ''))) > 120 THEN
    RAISE EXCEPTION 'Le titre doit contenir entre 3 et 120 caractères'
      USING ERRCODE = 'check_violation';
  END IF;
  IF length(btrim(COALESCE(p_message, ''))) < 3 THEN
    RAISE EXCEPTION 'Le message est obligatoire' USING ERRCODE = 'check_violation';
  END IF;
  IF v_visuel IS NOT NULL AND v_visuel NOT LIKE v_dossier || '%' THEN
    RAISE EXCEPTION 'Le visuel doit appartenir à votre espace de brouillons privé'
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_visuel IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM storage.objects
     WHERE bucket_id = 'notifications-brouillons' AND name = v_visuel
  ) THEN
    RAISE EXCEPTION 'Le visuel de cette communication est introuvable'
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_role = 'fabricant' THEN
    v_fabricant_id := v_id_metier;
  ELSE
    v_distributeur_id := v_id_metier;
    IF NOT EXISTS (
      SELECT 1 FROM distributeurs d
       WHERE d.id = v_distributeur_id AND d.statut = 'actif'
    ) THEN
      RAISE EXCEPTION 'Distributeur introuvable ou inactif'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  INSERT INTO notifications (
    emetteur_id, type, titre, message, cible, commune, visuel_url,
    statut_validation, fabricant_id, distributeur_id
  ) VALUES (
    v_auteur, p_type::type_notification, btrim(p_titre), btrim(p_message),
    'points_de_vente', v_commune, v_visuel,
    'en_attente', v_fabricant_id, v_distributeur_id
  ) RETURNING id INTO v_id_metier;

  RETURN jsonb_build_object('diffusion_id', v_id_metier, 'statut', 'en_attente');
END;
$fn$;

CREATE OR REPLACE FUNCTION diffuser_communication_admin(
  p_type TEXT,
  p_titre TEXT,
  p_message TEXT,
  p_visuel_url TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_auteur UUID := auth_utilisateur_id();
  v_visuel TEXT := NULLIF(btrim(COALESCE(p_visuel_url, '')), '');
  v_id UUID;
BEGIN
  IF NOT est_admin() OR v_auteur IS NULL THEN
    RAISE EXCEPTION 'Seul l''administrateur peut diffuser directement une communication'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_type NOT IN ('notification', 'splash_publicitaire') THEN
    RAISE EXCEPTION 'Type de communication invalide' USING ERRCODE = 'check_violation';
  END IF;
  IF length(btrim(COALESCE(p_titre, ''))) < 3
     OR length(btrim(COALESCE(p_titre, ''))) > 120
     OR length(btrim(COALESCE(p_message, ''))) < 3 THEN
    RAISE EXCEPTION 'Le titre et le message sont obligatoires'
      USING ERRCODE = 'check_violation';
  END IF;
  IF p_type = 'splash_publicitaire' AND v_visuel IS NULL THEN
    RAISE EXCEPTION 'Une publicité doit contenir un visuel'
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_visuel IS NOT NULL AND (
    v_visuel NOT LIKE v_auteur::TEXT || '/communications/%'
    OR NOT EXISTS (
      SELECT 1 FROM storage.objects
       WHERE bucket_id = 'notifications-brouillons' AND name = v_visuel
    )
  ) THEN
    RAISE EXCEPTION 'Le visuel privé est introuvable ou ne vous appartient pas'
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO notifications (
    emetteur_id, type, titre, message, cible, visuel_url,
    statut_validation, date_envoi
  ) VALUES (
    v_auteur, p_type::type_notification, btrim(p_titre), btrim(p_message),
    'points_de_vente', v_visuel, 'publiee', now()
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$fn$;

CREATE OR REPLACE FUNCTION valider_communication(p_diffusion_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_nb INTEGER;
BEGIN
  IF NOT est_admin() THEN
    RAISE EXCEPTION 'Seul l''administrateur peut approuver une communication'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE notifications
     SET statut_validation = 'publiee',
         valide_par = auth_utilisateur_id(),
         date_envoi = now(),
         motif_refus = NULL
   WHERE id = p_diffusion_id
     AND statut_validation = 'en_attente';
  GET DIAGNOSTICS v_nb = ROW_COUNT;
  RETURN v_nb = 1;
END;
$fn$;

CREATE OR REPLACE FUNCTION refuser_communication(
  p_diffusion_id UUID,
  p_motif TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_nb INTEGER;
BEGIN
  IF NOT est_admin() THEN
    RAISE EXCEPTION 'Seul l''administrateur peut refuser une communication'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE notifications
     SET statut_validation = 'refusee',
         valide_par = auth_utilisateur_id(),
         motif_refus = NULLIF(btrim(COALESCE(p_motif, '')), '')
   WHERE id = p_diffusion_id
     AND statut_validation = 'en_attente';
  GET DIAGNOSTICS v_nb = ROW_COUNT;
  RETURN v_nb = 1;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION soumettre_communication(TEXT, TEXT, TEXT, TEXT, TEXT),
                          diffuser_communication_admin(TEXT, TEXT, TEXT, TEXT),
                          valider_communication(UUID),
                          refuser_communication(UUID, TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION soumettre_communication(TEXT, TEXT, TEXT, TEXT, TEXT),
                         diffuser_communication_admin(TEXT, TEXT, TEXT, TEXT),
                         valider_communication(UUID),
                         refuser_communication(UUID, TEXT)
  TO authenticated;

CREATE VIEW v_diffusions_a_valider
WITH (security_invoker = on) AS
SELECT
  n.id AS diffusion_id,
  n.type,
  n.titre,
  n.message,
  n.commune,
  n.visuel_url,
  n.fabricant_id,
  n.distributeur_id,
  n.cree_le,
  u.nom AS emetteur,
  u.role::TEXT AS role_emetteur,
  CASE
    WHEN n.fabricant_id IS NOT NULL THEN f.nom
    WHEN n.distributeur_id IS NOT NULL THEN d.nom
    ELSE u.nom
  END AS organisation
FROM notifications n
JOIN utilisateurs u ON u.id = n.emetteur_id
LEFT JOIN fabricants f ON f.id = n.fabricant_id
LEFT JOIN distributeurs d ON d.id = n.distributeur_id
WHERE n.statut_validation = 'en_attente'
  AND est_admin();

CREATE VIEW v_mes_communications
WITH (security_invoker = on) AS
SELECT
  n.id AS diffusion_id,
  n.type,
  n.titre,
  n.message,
  n.visuel_url,
  n.statut_validation,
  n.cree_le,
  n.date_envoi,
  n.motif_refus
FROM notifications n
WHERE n.emetteur_id = auth_utilisateur_id()
  AND (n.fabricant_id IS NOT NULL OR n.distributeur_id IS NOT NULL);

CREATE OR REPLACE VIEW v_diffusions
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
       WHERE p.statut = 'actif'
         AND (n.commune IS NULL OR p.commune = n.commune)
         AND (n.fabricant_id IS NULL OR EXISTS (
           SELECT 1 FROM attributions_reseau ar
            WHERE ar.point_de_vente_id = p.id AND ar.fabricant_id = n.fabricant_id
         ))
         AND (n.distributeur_id IS NULL OR EXISTS (
           SELECT 1 FROM attributions_reseau ar
            WHERE ar.point_de_vente_id = p.id AND ar.distributeur_id = n.distributeur_id
         ))
    )
    WHEN 'distributeurs' THEN (SELECT count(*) FROM distributeurs WHERE statut = 'actif')
    WHEN 'fabricants' THEN (SELECT count(*) FROM fabricants WHERE statut = 'actif')
    WHEN 'livreurs' THEN (SELECT count(*) FROM livreurs WHERE actif)
    ELSE (SELECT count(*) FROM points_de_vente WHERE statut = 'actif')
       + (SELECT count(*) FROM fabricants WHERE statut = 'actif')
       + (SELECT count(*) FROM distributeurs WHERE statut = 'actif')
       + (SELECT count(*) FROM livreurs WHERE actif)
  END AS portee,
  n.visuel_url,
  n.statut_validation,
  n.cree_le,
  n.fabricant_id,
  n.distributeur_id
FROM notifications n
LEFT JOIN utilisateurs u ON u.id = n.emetteur_id
WHERE n.statut_validation = 'publiee';