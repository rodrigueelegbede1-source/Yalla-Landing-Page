-- 20260921006000_diffusions_recues.sql
--
-- Le bout manquant de la diffusion : la réception.
--
-- ── LE DÉFAUT QUE CETTE MIGRATION FERME ─────────────────────────────────────
--
-- La migration précédente a donné à l'administrateur de quoi émettre une
-- notification, un splash ou un sondage. Elle ne donnait à personne de quoi
-- les recevoir. Les politiques posées alors couvraient l'émetteur et
-- l'administrateur ; aucune ne permettait à un destinataire de lire ce qui lui
-- était adressé.
--
-- Concrètement : la diffusion partait, était stockée, sa portée était comptée,
-- et personne ne la voyait jamais. Rien ne le signalait, ni à l'écran ni dans
-- les journaux, parce qu'aucune erreur ne se produisait. Un aller sans retour.
--
-- ── QUI REÇOIT QUOI ─────────────────────────────────────────────────────────
--
-- La cible désigne un rôle, la commune restreint géographiquement, et les deux
-- se combinent. Un compte reçoit une diffusion si :
--
--   * elle vise le réseau complet, ou le rôle qui est le sien ;
--   * ET elle ne restreint aucune commune, ou restreint la sienne.
--
-- La commune n'est connue que d'un point de vente. Pour les autres rôles, une
-- diffusion communale n'a pas de sens et ne les atteint donc pas, ce qui est
-- la lecture la plus sûre : mieux vaut ne pas livrer un message que de le
-- livrer à quelqu'un qu'il ne concerne pas.

-- La commune du point de vente de l'appelant, ou NULL.
--
-- SECURITY DEFINER, et c'est indispensable. Cette fonction est appelée DEPUIS
-- une politique posée sur `notifications`. Si elle lisait `points_de_vente`
-- sous les droits de l'appelant, la politique de cette table-là s'appliquerait
-- à son tour, et le coût comme le risque de récursion grimperaient sans
-- bénéfice : la fonction ne rend qu'un nom de commune, celui du point de vente
-- de l'appelant lui-même, qu'il a déjà le droit de lire.
CREATE OR REPLACE FUNCTION commune_du_point_de_vente_courant()
RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT commune FROM points_de_vente
   WHERE id = auth_id_metier() AND auth_role() = 'point_de_vente';
$fn$;

-- Un REVOKE ici casserait les politiques qui l'appellent : PostgreSQL évalue
-- une politique sous l'identité de l'appelant, et sans EXECUTE la lecture
-- échoue pour tout le monde. La leçon vient de la migration sur la récursion
-- RLS, où le même réflexe avait bloqué toutes les lectures d'une table.
GRANT EXECUTE ON FUNCTION commune_du_point_de_vente_courant TO authenticated;

CREATE POLICY notifications_destinataire ON notifications FOR SELECT TO authenticated
  USING (
    (
      cible = 'reseau_complet'
      OR (cible = 'points_de_vente' AND auth_role() = 'point_de_vente')
      OR (cible = 'distributeurs'   AND auth_role() = 'distributeur')
      OR (cible = 'fabricants'      AND auth_role() = 'fabricant')
      OR (cible = 'livreurs'        AND auth_role() = 'livreur')
    )
    AND (
      commune IS NULL
      OR commune = commune_du_point_de_vente_courant()
    )
  );

-- Ce que le destinataire voit de ce qui lui est adressé.
--
-- Les options d'un sondage et la réponse déjà donnée voyagent avec la
-- diffusion, en JSON. L'écran mobile n'a ainsi qu'une seule lecture à faire :
-- sur un réseau où un appel sur dix se coupe, trois requêtes pour afficher une
-- liste sont trois occasions d'échouer.
CREATE VIEW v_mes_diffusions
WITH (security_invoker = on) AS
SELECT
  n.id AS diffusion_id,
  n.type,
  n.titre,
  n.message,
  n.date_envoi,
  EXTRACT(EPOCH FROM (now() - n.date_envoi))::INTEGER AS anciennete_secondes,
  (
    SELECT jsonb_agg(jsonb_build_object('id', o.id, 'libelle', o.libelle) ORDER BY o.libelle)
      FROM sondage_options o WHERE o.notification_id = n.id
  ) AS options,
  (
    SELECT r.option_choisie_id FROM sondage_reponses r
     WHERE r.notification_id = n.id AND r.point_de_vente_id = auth_id_metier()
  ) AS ma_reponse
FROM notifications n;

COMMENT ON VIEW v_mes_diffusions IS
  'Les diffusions adressées à l''appelant. Le filtrage vient des politiques de notifications, pas d''un WHERE : une vue qui refiltre ce que RLS a déjà filtré finit par diverger.';

-- Répondre à un sondage.
--
-- UNE SEULE RÉPONSE PAR BOUTIQUE, garantie par l'index unique de la table. On
-- choisit de remplacer plutôt que de refuser : un boutiquier qui touche la
-- mauvaise ligne sur un téléphone doit pouvoir se corriger, et un sondage dont
-- la première réponse est définitive mesure surtout la précision du doigt.
CREATE OR REPLACE FUNCTION repondre_sondage(
  p_notification_id UUID,
  p_option_id       UUID
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_pdv UUID := auth_id_metier();
BEGIN
  IF auth_role() <> 'point_de_vente' OR v_pdv IS NULL THEN
    RAISE EXCEPTION 'Seul un point de vente répond à un sondage'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- L'option doit appartenir AU sondage qu'on prétend renseigner. Sans ce
  -- contrôle, un client malveillant pourrait attribuer à un sondage la réponse
  -- d'un autre, et fausser un dépouillement sans qu'aucune contrainte de clé
  -- étrangère ne s'y oppose : les deux identifiants sont valides séparément.
  IF NOT EXISTS (
    SELECT 1 FROM sondage_options
     WHERE id = p_option_id AND notification_id = p_notification_id
  ) THEN
    RAISE EXCEPTION 'Cette réponse n''appartient pas à ce sondage'
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO sondage_reponses (notification_id, point_de_vente_id, option_choisie_id)
  VALUES (p_notification_id, v_pdv, p_option_id)
  ON CONFLICT (notification_id, point_de_vente_id)
  DO UPDATE SET option_choisie_id = p_option_id, date_reponse = now();

  RETURN jsonb_build_object('enregistree', true, 'option_id', p_option_id);
END;
$fn$;

REVOKE EXECUTE ON FUNCTION repondre_sondage FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION repondre_sondage TO authenticated;

-- Les diffusions entrent dans la publication temps réel, comme les ruptures et
-- les livraisons. Une consigne urgente qui attend le prochain rafraîchissement
-- manuel n'est pas une consigne urgente.
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
