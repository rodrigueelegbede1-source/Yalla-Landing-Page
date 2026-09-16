-- 20260916008100_hook_search_path.sql
--
-- Corrige le hook d'émission de jeton, qui faisait échouer toute connexion.
--
-- SYMPTÔME : HTTP 500 sur `/token`, avec le message opaque
-- « Error running hook URI ». La réponse de l'API ne dit rien de la cause ;
-- seuls les journaux d'authentification du projet la donnent :
--
--     ERROR: type "role_utilisateur" does not exist (SQLSTATE 42704)
--
-- CAUSE : le hook n'est pas exécuté par `postgres` mais par
-- `supabase_auth_admin`, dont le `search_path` ne contient pas `public`. La
-- déclaration `v_role role_utilisateur` était donc irrésolvable, alors même que
-- la fonction marchait parfaitement appelée à la main.
--
-- C'est le genre de panne qui coûte une soirée : la fonction est juste, les
-- droits sont bons, et pourtant rien ne marche, parce que le rôle qui l'exécute
-- ne voit pas le même schéma. Deux protections plutôt qu'une sont posées ici :
-- `SET search_path` sur la fonction, ET qualification explicite de chaque
-- objet. La seconde suffirait, mais la première protège les ajouts futurs.

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event JSONB)
RETURNS JSONB
LANGUAGE plpgsql STABLE
SET search_path = public   -- sans quoi supabase_auth_admin ne voit ni les types ni les tables
AS $fn$
DECLARE
  v_claims    JSONB;
  v_u_id      UUID;
  v_role      public.role_utilisateur;
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

GRANT EXECUTE ON FUNCTION public.custom_access_token_hook TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook FROM authenticated, anon, public;
