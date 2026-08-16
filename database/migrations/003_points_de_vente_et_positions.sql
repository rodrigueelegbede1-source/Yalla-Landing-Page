-- 003_points_de_vente_et_positions.sql

CREATE TABLE points_de_vente (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nom                 TEXT NOT NULL,
  type_activite       type_activite NOT NULL,
  adresse             TEXT,
  commune             TEXT NOT NULL,
  ville               TEXT NOT NULL DEFAULT 'Abidjan',
  position            GEOGRAPHY(POINT, 4326) NOT NULL,
  gerant_nom          TEXT,
  telephone           TEXT,
  statut              statut_point_de_vente NOT NULL DEFAULT 'en_attente_activation',
  agent_recenseur_id  UUID REFERENCES agents_recenseurs(id) ON DELETE SET NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_points_de_vente_position ON points_de_vente USING GIST(position);
CREATE INDEX idx_points_de_vente_commune ON points_de_vente(commune);
CREATE INDEX idx_points_de_vente_statut ON points_de_vente(statut);
CREATE INDEX idx_points_de_vente_agent ON points_de_vente(agent_recenseur_id);

CREATE TRIGGER trg_points_de_vente_updated_at
  BEFORE UPDATE ON points_de_vente
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Historique horodaté des positions des livreurs.
-- Fréquence applicative attendue : ~10 s (ou 25-30 m parcourus) en course active,
-- ~1/min à l'arrêt, aucune écriture hors ligne. Prévoir une purge/archivage au-delà
-- d'une fenêtre glissante (ex. 30 jours) : voir 009_maintenance.sql.
CREATE TABLE positions_livreurs (
  id          BIGSERIAL PRIMARY KEY,
  livreur_id  UUID NOT NULL REFERENCES livreurs(id) ON DELETE CASCADE,
  position    GEOGRAPHY(POINT, 4326) NOT NULL,
  horodatage  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_positions_livreurs_livreur_temps ON positions_livreurs(livreur_id, horodatage DESC);
CREATE INDEX idx_positions_livreurs_position ON positions_livreurs USING GIST(position);

-- Maintient livreurs.position / position_maj_le à jour à chaque nouvelle position historisée,
-- pour éviter à l'API de rejouer l'historique juste pour afficher la carte en temps réel.
CREATE OR REPLACE FUNCTION sync_derniere_position_livreur()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE livreurs
  SET position = NEW.position,
      position_maj_le = NEW.horodatage
  WHERE id = NEW.livreur_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_positions_livreurs_sync
  AFTER INSERT ON positions_livreurs
  FOR EACH ROW EXECUTE FUNCTION sync_derniere_position_livreur();
