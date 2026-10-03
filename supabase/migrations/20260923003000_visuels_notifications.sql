-- Visuel facultatif pour les messages réseau.
-- Les visuels ne contiennent pas de données privées : le bucket est public afin
-- que les appareils destinataires puissent les charger sans jeton expiré.

ALTER TABLE notifications ADD COLUMN IF NOT EXISTS visuel_url TEXT;
COMMENT ON COLUMN notifications.visuel_url IS
  'URL publique facultative du visuel joint au message';

INSERT INTO storage.buckets (id, name, public)
VALUES ('notifications', 'notifications', true)
ON CONFLICT (id) DO UPDATE SET public = true;

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

DROP FUNCTION IF EXISTS diffuser_notification(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT[]);

CREATE OR REPLACE FUNCTION diffuser_notification(
  p_type TEXT,
  p_titre TEXT,
  p_message TEXT,
  p_cible TEXT,
  p_commune TEXT,
  p_options TEXT[],
  p_visuel_url TEXT
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_id UUID;
  v_option TEXT;
  v_portee INTEGER;
  v_commune TEXT := NULLIF(trim(COALESCE(p_commune, '')), '');
  v_visuel TEXT := NULLIF(trim(COALESCE(p_visuel_url, '')), '');
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
  IF p_type = 'sondage' AND (p_options IS NULL OR array_length(array_remove(p_options, ''), 1) < 2) THEN
    RAISE EXCEPTION 'Un sondage demande au moins deux réponses possibles' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO notifications (emetteur_id, type, titre, message, cible, commune, visuel_url)
  VALUES (auth_utilisateur_id(), p_type::type_notification, trim(p_titre), trim(p_message),
          p_cible::cible_notification, v_commune, v_visuel)
  RETURNING id INTO v_id;

  IF p_type = 'sondage' THEN
    FOREACH v_option IN ARRAY p_options LOOP
      IF length(trim(COALESCE(v_option, ''))) > 0 THEN
        INSERT INTO sondage_options (notification_id, libelle) VALUES (v_id, trim(v_option));
      END IF;
    END LOOP;
  END IF;

  SELECT portee INTO v_portee FROM v_diffusions WHERE diffusion_id = v_id;
  RETURN jsonb_build_object('diffusion_id', v_id, 'portee', COALESCE(v_portee, 0),
    'cible', p_cible, 'commune', v_commune, 'visuel_url', v_visuel);
END;
$fn$;

REVOKE EXECUTE ON FUNCTION diffuser_notification(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT[], TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION diffuser_notification(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT[], TEXT)
  TO authenticated;

-- Compatibilité avec les consoles qui n'envoient pas encore de visuel.
CREATE OR REPLACE FUNCTION diffuser_notification(
  p_type TEXT, p_titre TEXT, p_message TEXT,
  p_cible TEXT DEFAULT 'reseau_complet', p_commune TEXT DEFAULT NULL,
  p_options TEXT[] DEFAULT NULL
)
RETURNS JSONB
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $fn$
  SELECT diffuser_notification(p_type, p_titre, p_message, p_cible, p_commune, p_options, NULL::TEXT);
$fn$;
REVOKE EXECUTE ON FUNCTION diffuser_notification(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT[])
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION diffuser_notification(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT[])
  TO authenticated;

-- Les nouvelles colonnes sont ajoutées en fin pour préserver les contrats de
-- vues déjà consommés par l'application.
DROP VIEW IF EXISTS v_diffusions;
CREATE VIEW v_diffusions WITH (security_invoker = on) AS
SELECT n.id AS diffusion_id, n.type, n.titre, n.message, n.cible, n.commune,
  n.date_envoi, u.nom AS emetteur,
  (SELECT count(*) FROM sondage_options o WHERE o.notification_id = n.id) AS options,
  (SELECT count(*) FROM sondage_reponses r WHERE r.notification_id = n.id) AS reponses,
  CASE n.cible
    WHEN 'points_de_vente' THEN (SELECT count(*) FROM points_de_vente p WHERE p.statut='actif' AND (n.commune IS NULL OR p.commune=n.commune))
    WHEN 'fabricants' THEN (SELECT count(*) FROM fabricants WHERE statut='actif')
    WHEN 'distributeurs' THEN (SELECT count(*) FROM distributeurs WHERE statut='actif')
    WHEN 'livreurs' THEN (SELECT count(*) FROM livreurs WHERE actif)
    ELSE (SELECT count(*) FROM points_de_vente WHERE statut='actif' AND (n.commune IS NULL OR commune=n.commune))
       + (SELECT count(*) FROM fabricants WHERE statut='actif')
       + (SELECT count(*) FROM distributeurs WHERE statut='actif')
       + (SELECT count(*) FROM livreurs WHERE actif)
  END AS portee,
  n.visuel_url
FROM notifications n LEFT JOIN utilisateurs u ON u.id=n.emetteur_id;

DROP VIEW IF EXISTS v_mes_diffusions;
CREATE VIEW v_mes_diffusions WITH (security_invoker = on) AS
SELECT n.id AS diffusion_id, n.type, n.titre, n.message, n.date_envoi,
  EXTRACT(EPOCH FROM (now()-n.date_envoi))::INTEGER AS anciennete_secondes,
  (SELECT jsonb_agg(jsonb_build_object('id',o.id,'libelle',o.libelle) ORDER BY o.libelle)
   FROM sondage_options o WHERE o.notification_id=n.id) AS options,
  (SELECT r.option_choisie_id FROM sondage_reponses r
   WHERE r.notification_id=n.id AND r.point_de_vente_id=auth_id_metier()) AS ma_reponse,
  n.visuel_url
FROM notifications n;
