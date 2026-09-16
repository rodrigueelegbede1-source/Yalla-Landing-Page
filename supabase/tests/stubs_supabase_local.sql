-- stubs_supabase_local.sql
--
-- Simule le strict minimum de ce que Supabase fournit, pour pouvoir appliquer et
-- tester les migrations sur un PostgreSQL ordinaire, sans projet Supabase ni
-- Docker.
--
-- À quoi ça sert : valider la syntaxe SQL, l'ordre des dépendances, les triggers
-- et les fonctions avant de pousser quoi que ce soit en ligne. Un `supabase db
-- push` qui échoue à mi-parcours laisse la base dans un état bâtard, autant
-- échouer ici.
--
-- CE QUE CE FICHIER NE TESTE PAS, et qu'il ne faut pas croire testé :
--   * le comportement réel des politiques RLS sous une vraie identité Supabase
--   * le hook d'émission de jeton, appelé par le service d'authentification
--   * la diffusion Realtime
--   * l'exécution effective des tâches pg_cron
-- Tout cela exige un vrai projet Supabase.
--
--   psql -d yalla_test -f supabase/tests/stubs_supabase_local.sql

-- ── Rôles attendus par les GRANT des migrations ────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
    CREATE ROLE supabase_auth_admin NOLOGIN;
  END IF;
END $$;

-- ── Schéma auth ────────────────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS auth;

CREATE TABLE IF NOT EXISTS auth.users (
  id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE
);

-- `auth.uid()` rend l'utilisateur courant sur Supabase. En local, on le pose à
-- la main avec `SET request.jwt.claims = '...'` pour jouer un rôle donné.
CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID
LANGUAGE sql STABLE AS $fn$
  SELECT NULLIF(
    NULLIF(current_setting('request.jwt.claims', true), '')::JSONB ->> 'sub',
    ''
  )::UUID;
$fn$;

CREATE OR REPLACE FUNCTION auth.jwt() RETURNS JSONB
LANGUAGE sql STABLE AS $fn$
  SELECT COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::JSONB, '{}'::JSONB);
$fn$;

-- ── Publication Realtime ───────────────────────────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $$;

-- ── pg_cron simulé ─────────────────────────────────────────────────────────
-- L'extension n'est pas disponible sur un PostgreSQL ordinaire. On enregistre
-- les tâches sans les exécuter : cela suffit à vérifier que les appels de la
-- migration sont bien formés.
CREATE SCHEMA IF NOT EXISTS cron;

CREATE TABLE IF NOT EXISTS cron.job (
  jobid    BIGSERIAL PRIMARY KEY,
  jobname  TEXT UNIQUE,
  schedule TEXT,
  command  TEXT
);

CREATE TABLE IF NOT EXISTS cron.job_run_details (
  jobid    BIGINT,
  end_time TIMESTAMPTZ
);

CREATE OR REPLACE FUNCTION cron.schedule(p_nom TEXT, p_schedule TEXT, p_commande TEXT)
RETURNS BIGINT
LANGUAGE plpgsql AS $fn$
DECLARE v_id BIGINT;
BEGIN
  INSERT INTO cron.job (jobname, schedule, command)
  VALUES (p_nom, p_schedule, p_commande)
  ON CONFLICT (jobname) DO UPDATE SET schedule = EXCLUDED.schedule, command = EXCLUDED.command
  RETURNING jobid INTO v_id;
  RETURN v_id;
END;
$fn$;
