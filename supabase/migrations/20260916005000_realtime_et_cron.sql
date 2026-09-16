-- 20260916005000_realtime_et_cron.sql
--
-- Remplace les deux services d'arrière-plan du backend NestJS par des mécanismes
-- de la base elle-même.
--
--   `RealtimeGateway` (socket.io)  ->  Supabase Realtime
--   `EscaladeService` (setInterval) ->  pg_cron
--
-- Ce n'est pas qu'une économie d'hébergement. La passerelle socket.io avait un
-- défaut de conception : le message `rejoindre` faisait `client.join(room)` sans
-- aucune vérification, si bien que n'importe quel client pouvait rejoindre la
-- room `reseau:global` ou celle d'un fabricant arbitraire et recevoir tout le
-- flux. Supabase Realtime, lui, diffuse à travers les politiques RLS : un
-- distributeur ne reçoit que les lignes qu'il a le droit de lire. La faille
-- disparaît par construction, elle n'est pas corrigée mais supprimée.

-- ── 1. Extensions ──────────────────────────────────────────────────────────

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ── 2. Diffusion temps réel ────────────────────────────────────────────────
--
-- Deux tables seulement. Diffuser les ventes ou les stocks serait à la fois
-- inutile et contraire à la promesse faite au boutiquier que sa caisse reste
-- privée.

ALTER PUBLICATION supabase_realtime ADD TABLE ruptures;
ALTER PUBLICATION supabase_realtime ADD TABLE positions_livreurs;

-- REPLICA IDENTITY FULL : sans cela, un événement de mise à jour ne transporte
-- que la clé primaire. Les politiques RLS ne pourraient pas décider qui a le
-- droit de le recevoir, et l'événement serait filtré pour tout le monde.
ALTER TABLE ruptures           REPLICA IDENTITY FULL;
ALTER TABLE positions_livreurs REPLICA IDENTITY FULL;

-- ── 3. Escalade planifiée ──────────────────────────────────────────────────
--
-- `escalader_ruptures_en_attente()` existe depuis la migration 011 et sa logique
-- est couverte par les tests. Elle n'était appelée que par un `setInterval` dans
-- le processus NestJS, ce qui posait deux problèmes : rien ne tournait quand
-- l'API était arrêtée, et plusieurs instances l'auraient déclenchée en parallèle.
--
-- Toutes les 5 minutes : le délai d'escalade se compte en heures, affiner
-- davantage chargerait la base sans rien changer pour le boutiquier.

SELECT cron.schedule(
  'escalade-ruptures',
  '*/5 * * * *',
  $cron$ SELECT escalader_ruptures_en_attente(); $cron$
);

-- La purge des positions existait aussi depuis la migration 009, et n'était
-- appelée par rien. Environ 86 000 lignes par jour pour 30 livreurs : sans
-- purge, la table devient le premier problème de performance du produit.
SELECT cron.schedule(
  'purge-positions-livreurs',
  '30 3 * * *',
  $cron$ SELECT purger_positions_livreurs_anciennes(); $cron$
);

-- ── 4. Purge du journal de pg_cron ─────────────────────────────────────────
--
-- Piège connu : `cron.job_run_details` conserve une ligne par exécution. À
-- raison d'une toutes les 5 minutes, cela fait plus de 100 000 lignes par an,
-- et la table finit par ralentir le planificateur lui-même.

SELECT cron.schedule(
  'purge-journal-cron',
  '0 4 * * 0',
  $cron$ DELETE FROM cron.job_run_details WHERE end_time < now() - INTERVAL '7 days'; $cron$
);

-- Les trois tâches planifiées sont consultables par : SELECT * FROM cron.job;
