-- 20260917003000_role_appelant_texte.sql
--
-- Corrige le refus d'un appel non authentifié, qui plantait au lieu de refuser.
--
-- SYMPTÔME :
--
--     ERROR: invalid input value for enum role_utilisateur: ""
--     CONTEXTE : during statement block local variable initialization
--
-- CAUSE : `creer_compte_metier` déclarait `v_createur role_utilisateur :=
-- auth_role()`. Or `auth_role()` rend du TEXTE, et **la chaîne vide** quand il
-- n'y a pas de jeton, ce que documente son propre commentaire. La conversion
-- implicite vers l'énumération échouait donc avant même d'entrer dans le corps
-- de la fonction, et le contrôle de périmètre placé juste en dessous n'était
-- jamais atteint.
--
-- Le contrôle n'était pas contournable pour autant : l'appel échouait, il
-- échouait simplement pour la mauvaise raison, avec un message incompréhensible
-- et un code SQLSTATE que l'application ne sait pas traduire. Un appelant sans
-- session lisait « L'opération a échoué » au lieu de « Authentification
-- requise », et rien ne l'orientait vers une reconnexion.
--
-- CORRECTION : comparer du texte à du texte, comme le font toutes les
-- politiques du fichier des périmètres (`auth_role() = 'distributeur'`). Le
-- rôle CRÉÉ, lui, reste bien typé : c'est une valeur qui entre en base.
--
-- La leçon vaut au-delà de cette fonction : `auth_role()` ne doit jamais être
-- affecté à une variable d'énumération.

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
  -- TEXT, et non role_utilisateur : `auth_role()` rend la chaîne vide hors session.
  v_createur        TEXT := auth_role();
  v_createur_metier UUID := auth_id_metier();
  v_tel             TEXT;
  v_u_id            UUID;
  v_id_metier       UUID;
BEGIN
  IF v_createur IS NULL OR v_createur = '' THEN
    RAISE EXCEPTION 'Authentification requise' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Qui a le droit de créer quoi. Le distributeur ne crée que des livreurs,
  -- l'agent ne crée que des boutiques et des distributeurs. Un agent ne peut
  -- donc pas se fabriquer un compte administrateur.
  IF NOT (
       v_createur = 'administrateur'
    OR (v_createur = 'agent_recenseur' AND p_role IN ('point_de_vente', 'distributeur'))
    OR (v_createur = 'distributeur'    AND p_role = 'livreur')
  ) THEN
    RAISE EXCEPTION 'Votre rôle ne permet pas de créer un compte « % »', p_role
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Treize chiffres, sans « + » : la forme que rend `normaliser_telephone`, et
  -- la même que produisent le Dart, la fonction Edge et le script d'amorçage.
  v_tel := normaliser_telephone(p_telephone);
  IF v_tel IS NULL OR length(v_tel) <> 13 OR left(v_tel, 3) <> '225' THEN
    RAISE EXCEPTION 'Numéro de téléphone invalide : %', p_telephone
      USING ERRCODE = 'check_violation';
  END IF;

  IF EXISTS (SELECT 1 FROM utilisateurs WHERE telephone = v_tel) THEN
    RAISE EXCEPTION 'Ce numéro est déjà rattaché à un compte Yalla'
      USING ERRCODE = 'unique_violation';
  END IF;

  INSERT INTO utilisateurs (nom, telephone, role, auth_user_id)
  VALUES (trim(p_nom), v_tel, p_role, p_auth_user_id)
  RETURNING id INTO v_u_id;

  IF p_role = 'point_de_vente' THEN
    INSERT INTO points_de_vente (
      nom, type_activite, commune, ville, adresse, position,
      gerant_nom, telephone, statut, agent_recenseur_id, utilisateur_id
    )
    VALUES (
      trim(p_details->>'nom_boutique'),
      (p_details->>'type_activite')::type_activite,
      trim(p_details->>'commune'),
      COALESCE(NULLIF(trim(p_details->>'ville'), ''), 'Abidjan'),
      NULLIF(trim(COALESCE(p_details->>'adresse', '')), ''),
      ST_SetSRID(ST_MakePoint(
        (p_details->>'longitude')::DOUBLE PRECISION,
        (p_details->>'latitude')::DOUBLE PRECISION
      ), 4326)::GEOGRAPHY,
      trim(p_nom),
      v_tel,
      'actif',
      CASE WHEN v_createur = 'agent_recenseur' THEN v_createur_metier ELSE NULL END,
      v_u_id
    )
    RETURNING id INTO v_id_metier;

  ELSIF p_role = 'distributeur' THEN
    INSERT INTO distributeurs (nom, telephone, utilisateur_id, fabricant_id, statut)
    VALUES (
      COALESCE(NULLIF(trim(COALESCE(p_details->>'nom_societe', '')), ''), trim(p_nom)),
      v_tel,
      v_u_id,
      NULLIF(p_details->>'fabricant_id', '')::UUID,
      'actif'
    )
    RETURNING id INTO v_id_metier;

  ELSIF p_role = 'livreur' THEN
    INSERT INTO livreurs (utilisateur_id, distributeur_id)
    VALUES (v_u_id, v_createur_metier)
    RETURNING id INTO v_id_metier;

  ELSIF p_role = 'agent_recenseur' THEN
    INSERT INTO agents_recenseurs (utilisateur_id, secteur)
    VALUES (v_u_id, COALESCE(NULLIF(trim(COALESCE(p_details->>'secteur', '')), ''), 'Abidjan'))
    RETURNING id INTO v_id_metier;
  END IF;

  RETURN jsonb_build_object(
    'utilisateur_id', v_u_id,
    'id_metier',      v_id_metier,
    'telephone',      v_tel,
    'role',           p_role
  );
END;
$fn$;
