-- 20260921002000_compte_fabricant.sql
--
-- `creer_compte_metier` ne savait pas créer un fabricant.
--
-- ── LE DÉFAUT, ET POURQUOI IL ÉTAIT INVISIBLE ───────────────────────────────
--
-- La fonction traitait quatre rôles sur cinq : point de vente, distributeur,
-- livreur, agent recenseur. Le rôle `fabricant` traversait la cascade de `IF`
-- sans rencontrer aucune branche, et la fonction rendait `id_metier: null`
-- SANS LEVER D'ERREUR.
--
-- La conséquence est exactement celle que la fonction Edge `creer-compte`
-- s'efforce d'éviter avec son annulation : un compte de connexion valide, une
-- ligne `utilisateurs` en place, et aucune ligne `fabricants` derrière. Le
-- fabricant se connecte, le jeton ne porte aucun `id_metier`, et toutes les
-- vues filtrées sur `auth_id_metier()` rendent zéro ligne. Il voit un tableau
-- de bord vide et rien ne lui dit pourquoi.
--
-- L'annulation de la fonction Edge ne le rattrapait pas : elle ne se déclenche
-- que sur erreur, et ici il n'y en avait aucune. Le défaut ne pouvait se
-- manifester qu'au premier fabricant validé depuis le tableau de bord
-- administrateur, c'est-à-dire au premier usage réel de l'écran.
--
-- ── CE QUE LA CORRECTION AJOUTE ─────────────────────────────────────────────
--
--   1. La branche `fabricant`, qui crée la ligne dans `fabricants`.
--   2. Un GARDE-FOU GÉNÉRAL : tout rôle qui devrait avoir une ligne métier et
--      n'en obtient pas fait désormais échouer la transaction. Le prochain rôle
--      ajouté à l'énumération et oublié ici produira une erreur franche, pas un
--      compte fantôme. C'est le vrai correctif ; la branche n'en est que le cas
--      particulier d'aujourd'hui.
--
-- ── UNE MARQUE EST UN FABRICANT, DANS CE SCHÉMA ─────────────────────────────
--
-- `fabricants` porte le nom sous lequel le boutiquier reconnaît le produit.
-- Un groupe qui exploite plusieurs marques distinctes se déclare donc autant de
-- fois. Cela paraît étrange vu du registre du commerce, mais c'est la seule
-- forme qui fonctionne sur le terrain : le boutiquier signale une rupture de
-- Céleste, il ne signale pas une rupture de la société qui l'embouteille, et
-- c'est la marque, pas la raison sociale, qui décide à quel distributeur la
-- course part.

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
  -- donc pas se fabriquer un compte administrateur, ni un compte fabricant :
  -- une marque engage le réseau entier, sa création reste à l'administrateur.
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

  ELSIF p_role = 'fabricant' THEN
    -- Le nom porté ici est celui que le boutiquier lit sur le paquet. À défaut
    -- de raison sociale déclarée, le nom de la personne fait un repère médiocre
    -- mais jamais vide, et l'administrateur peut le corriger ensuite.
    INSERT INTO fabricants (utilisateur_id, nom, statut)
    VALUES (
      v_u_id,
      COALESCE(NULLIF(trim(COALESCE(p_details->>'nom_societe', '')), ''), trim(p_nom)),
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

  -- LE GARDE-FOU. Seul l'administrateur n'a pas de table métier : son rôle
  -- n'existe que dans `utilisateurs`. Tout autre rôle qui ressort d'ici sans
  -- `id_metier` est un compte qui se connectera et ne verra rien, sans qu'aucun
  -- message ne l'explique. Mieux vaut que la création échoue bruyamment.
  IF v_id_metier IS NULL AND p_role <> 'administrateur' THEN
    RAISE EXCEPTION
      'Aucune ligne métier créée pour le rôle « % » : la fonction ne sait pas le traiter', p_role
      USING ERRCODE = 'feature_not_supported';
  END IF;

  RETURN jsonb_build_object(
    'utilisateur_id', v_u_id,
    'id_metier',      v_id_metier,
    'telephone',      v_tel,
    'role',           p_role
  );
END;
$fn$;

COMMENT ON FUNCTION creer_compte_metier IS
  'Crée la ligne utilisateur et la ligne métier d''un compte, sous l''identité de l''appelant. Échoue plutôt que de rendre un compte sans ligne métier.';
