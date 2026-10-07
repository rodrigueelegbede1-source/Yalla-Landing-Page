-- Référentiel PostGIS en lecture seule pour les clients.
-- Les références spatiales sont publiques, mais ne doivent pas être modifiables
-- depuis les rôles utilisés par l'application.
--
-- NOTE : cette table appartient à l'extension PostGIS (créée par un rôle
-- interne Supabase), pas au rôle "postgres" des migrations. `ALTER TABLE ...
-- ENABLE ROW LEVEL SECURITY` et `CREATE POLICY` échouent donc avec
-- "must be owner of table spatial_ref_sys" (SQLSTATE 42501) : on ne peut pas
-- activer la RLS dessus. La seule protection applicable sans être
-- propriétaire est de retirer les droits d'écriture des rôles applicatifs ;
-- la lecture reste nécessaire au fonctionnement normal de PostGIS.

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLE public.spatial_ref_sys
  FROM PUBLIC, anon, authenticated;

GRANT SELECT ON TABLE public.spatial_ref_sys TO anon, authenticated;