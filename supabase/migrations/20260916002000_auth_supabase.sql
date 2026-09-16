-- 20260916002000_auth_supabase.sql
--
-- Bascule de l'authentification maison vers Supabase Auth.
--
-- Avant : `utilisateurs.mot_de_passe_hash` (bcrypt) + JWT signé par NestJS, avec
-- l'ID métier transporté dans le jeton (voir le piège n°1 d'AGENTS.md §9).
-- Après : Supabase Auth détient les identifiants, et un hook injecte le rôle et
-- l'ID métier dans le jeton. Le contrat vu par l'application est le même, seule
-- la mécanique change.
--
-- Choix d'identifiant : le NUMÉRO DE TÉLÉPHONE, pas l'email. Les gérants de
-- boutique et les livreurs d'Abidjan n'ont pas tous une adresse email active,
-- mais tous ont un numéro. Le numéro est converti en adresse technique interne
-- (`2250706303030@yalla.ci`) parce que Supabase Auth exige un email ou un
-- téléphone vérifié par SMS, et que le SMS coûte de l'argent à chaque connexion.
-- Aucun courriel n'est jamais envoyé à ces adresses, elles ne servent que de clé.

-- ── 1. Le lien vers Supabase Auth ──────────────────────────────────────────
--
-- On AJOUTE une colonne plutôt que de faire de `utilisateurs.id` l'identifiant
-- Supabase : cinq tables de rôle référencent déjà `utilisateurs.id`, changer la
-- clé primaire casserait tout le graphe pour un gain nul.
--
-- Nullable à dessein : un compte peut être recensé sur le terrain avant d'être
-- provisionné dans Supabase Auth. La colonne se remplit à la création du compte.

ALTER TABLE utilisateurs
  ADD COLUMN auth_user_id UUID UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX idx_utilisateurs_auth_user ON utilisateurs(auth_user_id);

-- Supabase Auth gère désormais les mots de passe. Garder un hash ici serait au
-- mieux inutile, au pire une seconde source de vérité qui finit par diverger.
ALTER TABLE utilisateurs ALTER COLUMN mot_de_passe_hash DROP NOT NULL;
ALTER TABLE utilisateurs DROP COLUMN mot_de_passe_hash;

-- ── 2. Numéro de téléphone et adresse technique ────────────────────────────
--
-- Normalise un numéro ivoirien saisi sous n'importe quelle forme
-- (`07 06 30 30 30`, `+225 07 06 30 30 30`, `002250706303030`) vers `2250706303030`.

CREATE OR REPLACE FUNCTION normaliser_telephone(p_telephone TEXT)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE AS $fn$
DECLARE
  v TEXT;
BEGIN
  IF p_telephone IS NULL THEN RETURN NULL; END IF;

  -- On ne garde que les chiffres.
  v := regexp_replace(p_telephone, '[^0-9]', '', 'g');

  -- Préfixe international sous forme 00225 : on le ramène à 225.
  IF left(v, 5) = '00225' THEN v := substring(v from 3); END IF;

  -- Numéro national à 10 chiffres commençant par 0 : on préfixe l'indicatif.
  IF length(v) = 10 AND left(v, 1) = '0' THEN v := '225' || v; END IF;

  RETURN v;
END;
$fn$;

COMMENT ON FUNCTION normaliser_telephone IS
  'Ramène un numéro ivoirien à sa forme canonique 225XXXXXXXXXX, quelle que soit la saisie.';

-- L'adresse technique dérivée du numéro. C'est elle qui sert de login Supabase.
CREATE OR REPLACE FUNCTION email_technique(p_telephone TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $fn$
  SELECT normaliser_telephone(p_telephone) || '@yalla.ci';
$fn$;

COMMENT ON FUNCTION email_technique IS
  'Adresse interne dérivée du numéro, utilisée comme identifiant Supabase Auth. Aucun courriel n''y est jamais envoyé.';

-- Les numéros doivent être uniques sous leur forme normalisée, sinon deux
-- saisies différentes du même numéro créeraient deux comptes.
CREATE UNIQUE INDEX uq_utilisateurs_telephone_normalise
  ON utilisateurs(normaliser_telephone(telephone));

-- ── 3. Résolution de l'ID métier ───────────────────────────────────────────
--
-- Chaque rôle a sa table dédiée. Cette fonction rend l'identifiant métier
-- correspondant, celui que l'application utilise pour tout le reste.

CREATE OR REPLACE FUNCTION resoudre_id_metier(p_utilisateur_id UUID, p_role role_utilisateur)
RETURNS UUID
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_id UUID;
BEGIN
  CASE p_role
    WHEN 'fabricant'       THEN SELECT id INTO v_id FROM fabricants        WHERE utilisateur_id = p_utilisateur_id;
    WHEN 'distributeur'    THEN SELECT id INTO v_id FROM distributeurs     WHERE utilisateur_id = p_utilisateur_id;
    WHEN 'livreur'         THEN SELECT id INTO v_id FROM livreurs          WHERE utilisateur_id = p_utilisateur_id;
    WHEN 'point_de_vente'  THEN SELECT id INTO v_id FROM points_de_vente   WHERE utilisateur_id = p_utilisateur_id;
    WHEN 'agent_recenseur' THEN SELECT id INTO v_id FROM agents_recenseurs WHERE utilisateur_id = p_utilisateur_id;
    ELSE v_id := NULL; -- 'administrateur' n'a pas de table dédiée.
  END CASE;
  RETURN v_id;
END;
$fn$;

-- ── 4. Le hook qui enrichit le jeton ───────────────────────────────────────
--
-- Supabase appelle cette fonction à chaque émission de jeton. On y place le rôle
-- et l'ID métier, ce qui permet aux politiques RLS de les lire sans requête
-- supplémentaire. Sans ce hook, chaque politique devrait interroger
-- `utilisateurs` à chaque ligne évaluée, ce qui serait ruineux.

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event JSONB)
RETURNS JSONB
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
  v_claims    JSONB;
  v_u_id      UUID;
  v_role      role_utilisateur;
  v_id_metier UUID;
  v_nom       TEXT;
BEGIN
  SELECT u.id, u.role, u.nom
    INTO v_u_id, v_role, v_nom
    FROM public.utilisateurs u
   WHERE u.auth_user_id = (event->>'user_id')::UUID;

  v_claims := event->'claims';

  IF v_u_id IS NOT NULL THEN
    v_id_metier := public.resoudre_id_metier(v_u_id, v_role);

    v_claims := jsonb_set(v_claims, '{user_role}',      to_jsonb(v_role::TEXT));
    v_claims := jsonb_set(v_claims, '{utilisateur_id}', to_jsonb(v_u_id));
    v_claims := jsonb_set(v_claims, '{nom}',            to_jsonb(v_nom));
    -- Peut rester nul : un administrateur n'a pas d'ID métier, et un compte
    -- fraîchement créé peut ne pas encore avoir sa ligne de rôle.
    v_claims := jsonb_set(v_claims, '{id_metier}',
                          COALESCE(to_jsonb(v_id_metier), 'null'::JSONB));
  END IF;

  RETURN jsonb_set(event, '{claims}', v_claims);
END;
$fn$;

-- Le hook est exécuté par le service d'authentification, pas par l'utilisateur.
GRANT USAGE ON SCHEMA public TO supabase_auth_admin;
GRANT EXECUTE ON FUNCTION public.custom_access_token_hook TO supabase_auth_admin;
GRANT EXECUTE ON FUNCTION public.resoudre_id_metier       TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook FROM authenticated, anon, public;
GRANT SELECT ON TABLE public.utilisateurs TO supabase_auth_admin;

-- ── 5. Lecture du jeton, côté politiques ───────────────────────────────────
--
-- Trois fonctions d'aide, utilisées par toutes les politiques RLS de la
-- migration suivante. Marquées STABLE : PostgreSQL ne les réévalue pas ligne
-- par ligne, ce qui compte quand une politique filtre des milliers de ruptures.

CREATE OR REPLACE FUNCTION auth_role()
RETURNS TEXT LANGUAGE sql STABLE AS $fn$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::JSONB ->> 'user_role',
    ''
  );
$fn$;

CREATE OR REPLACE FUNCTION auth_id_metier()
RETURNS UUID LANGUAGE sql STABLE AS $fn$
  SELECT NULLIF(
    NULLIF(current_setting('request.jwt.claims', true), '')::JSONB ->> 'id_metier',
    'null'
  )::UUID;
$fn$;

CREATE OR REPLACE FUNCTION auth_utilisateur_id()
RETURNS UUID LANGUAGE sql STABLE AS $fn$
  SELECT NULLIF(
    NULLIF(current_setting('request.jwt.claims', true), '')::JSONB ->> 'utilisateur_id',
    'null'
  )::UUID;
$fn$;

COMMENT ON FUNCTION auth_role IS
  'Rôle de l''utilisateur courant, lu dans le jeton. Chaîne vide si non authentifié.';
COMMENT ON FUNCTION auth_id_metier IS
  'ID métier de l''utilisateur courant (fabricants.id, distributeurs.id, livreurs.id, points_de_vente.id...). Nul pour un administrateur.';

-- ── 6. Création d'un compte ────────────────────────────────────────────────
--
-- Le provisionnement d'un compte Supabase Auth ne peut pas se faire en SQL pur :
-- il passe par l'API d'administration. Cette fonction rattache une ligne
-- `utilisateurs` existante à un compte Auth déjà créé, et sert de point unique
-- pour ce lien.

CREATE OR REPLACE FUNCTION rattacher_compte_auth(p_telephone TEXT, p_auth_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_id UUID;
BEGIN
  UPDATE utilisateurs
     SET auth_user_id = p_auth_user_id
   WHERE normaliser_telephone(telephone) = normaliser_telephone(p_telephone)
     AND auth_user_id IS NULL
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Aucun utilisateur sans compte pour le numéro %', p_telephone
      USING ERRCODE = 'no_data_found';
  END IF;

  RETURN v_id;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION rattacher_compte_auth FROM authenticated, anon, public;
