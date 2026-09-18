-- 20260917004000_telephone_fixe.sql
--
-- Accepte les numéros fixes ivoiriens, que la normalisation refusait.
--
-- SYMPTÔME : « Numéro de téléphone invalide » sur un numéro parfaitement
-- valide, dès qu'il est saisi sans son indicatif. Découvert en inscrivant un
-- vrai fabricant, dont le seul numéro est un fixe de Treichville.
--
-- CAUSE : la règle disait « un numéro de dix chiffres COMMENÇANT PAR ZÉRO est
-- national, on lui préfixe 225 ». Elle vient de l'ancien plan de numérotation.
-- Depuis le passage à dix chiffres de 2021, la Côte d'Ivoire a cinq préfixes :
--
--     01, 05, 07  mobiles
--     25, 27      fixes
--
-- Les mobiles commencent bien par zéro, les fixes non. `2721219000` restait
-- donc à dix chiffres, était jugé trop court, et le compte ne pouvait pas être
-- créé. Un boutiquier avec un fixe était refusé, un boutiquier avec un mobile
-- passait, sans que rien n'explique la différence.
--
-- CORRECTION : tout numéro de dix chiffres est national, quel que soit son
-- premier chiffre.
--
-- PAS D'AMBIGUÏTÉ INTRODUITE : aucun préfixe ivoirien ne commence par « 22 »,
-- donc un nombre de dix chiffres ne peut jamais être confondu avec un indicatif
-- suivi d'un numéro tronqué.
--
-- CE QUI N'EST PAS CORRIGÉ, et c'est délibéré : l'ancien format à huit chiffres
-- (`21 21 90 00`) reste refusé. Il n'est plus attribué depuis 2021, et deviner
-- le préfixe à lui ajouter serait deviner faux une fois sur deux.
--
-- LES QUATRE IMPLÉMENTATIONS doivent rester identiques : celle-ci, celle de
-- `mobile/lib/core/telephone.dart`, celle de la fonction Edge `creer-compte`,
-- et celle des scripts shell. Une divergence crée un compte sous une adresse
-- et le fait se connecter sous une autre.

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

  -- Tout numéro national fait dix chiffres depuis 2021, mobile comme fixe.
  -- La condition ne porte plus sur le premier chiffre : les fixes commencent
  -- par 25 ou 27, et étaient rejetés.
  IF length(v) = 10 THEN v := '225' || v; END IF;

  RETURN v;
END;
$fn$;

COMMENT ON FUNCTION normaliser_telephone IS
  'Ramène un numéro ivoirien à sa forme canonique 225XXXXXXXXXX. Accepte mobiles (01, 05, 07) et fixes (25, 27), avec ou sans indicatif.';
