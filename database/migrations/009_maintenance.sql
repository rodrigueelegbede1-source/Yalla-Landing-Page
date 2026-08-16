-- 009_maintenance.sql
-- Purge de l'historique des positions au-delà d'une fenêtre glissante de 30 jours
-- (volumétrie anticipée dans Yalla_Stack_Technique.md : ~86 000 lignes/jour à pleine charge).
-- À planifier via pg_cron si disponible sur l'hébergeur, sinon via un job planifié
-- côté backend NestJS (ex. @nestjs/schedule, une fois par nuit).

CREATE OR REPLACE FUNCTION purger_positions_livreurs_anciennes()
RETURNS void AS $$
BEGIN
  DELETE FROM positions_livreurs
  WHERE horodatage < now() - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql;

-- Si l'extension pg_cron est disponible sur NindoHost, décommenter pour une purge
-- automatique quotidienne à 3h du matin :
-- SELECT cron.schedule('purge-positions-livreurs', '0 3 * * *', 'SELECT purger_positions_livreurs_anciennes();');
