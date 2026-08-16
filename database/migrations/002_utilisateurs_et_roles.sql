-- 002_utilisateurs_et_roles.sql
-- Compte de connexion commun, puis une table par rôle pour les champs spécifiques.

CREATE TABLE utilisateurs (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nom                TEXT NOT NULL,
  telephone          TEXT NOT NULL UNIQUE,
  email              TEXT UNIQUE,
  mot_de_passe_hash  TEXT NOT NULL,
  role               role_utilisateur NOT NULL,
  derniere_connexion TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_utilisateurs_updated_at
  BEFORE UPDATE ON utilisateurs
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE agents_recenseurs (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  utilisateur_id UUID NOT NULL UNIQUE REFERENCES utilisateurs(id) ON DELETE CASCADE,
  secteur        TEXT NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_agents_recenseurs_updated_at
  BEFORE UPDATE ON agents_recenseurs
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE fabricants (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  utilisateur_id UUID NOT NULL UNIQUE REFERENCES utilisateurs(id) ON DELETE CASCADE,
  nom            TEXT NOT NULL,
  statut         statut_fabricant NOT NULL DEFAULT 'actif',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_fabricants_updated_at
  BEFORE UPDATE ON fabricants
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE livreurs (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  utilisateur_id UUID NOT NULL UNIQUE REFERENCES utilisateurs(id) ON DELETE CASCADE,
  fabricant_id   UUID NOT NULL REFERENCES fabricants(id) ON DELETE RESTRICT,
  en_ligne       BOOLEAN NOT NULL DEFAULT false,
  -- Dernière position connue, dénormalisée depuis positions_livreurs pour des lectures rapides (carte).
  position       GEOGRAPHY(POINT, 4326),
  position_maj_le TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_livreurs_fabricant ON livreurs(fabricant_id);
CREATE INDEX idx_livreurs_position ON livreurs USING GIST(position);

CREATE TRIGGER trg_livreurs_updated_at
  BEFORE UPDATE ON livreurs
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
