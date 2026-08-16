-- 004_catalogue_et_attribution.sql

-- Table de référence plutôt qu'un enum : permet d'ajouter des catégories
-- (l'énoncé du cahier des charges les décrit comme extensibles) sans migration de schéma.
CREATE TABLE categories_produit (
  id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nom  TEXT NOT NULL UNIQUE
);

INSERT INTO categories_produit (nom) VALUES
  ('Boissons'), ('Épicerie'), ('Hygiène'), ('Snacking');

CREATE TABLE produits (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  fabricant_id  UUID NOT NULL REFERENCES fabricants(id) ON DELETE CASCADE,
  nom           TEXT NOT NULL,
  reference     TEXT NOT NULL,
  categorie_id  UUID REFERENCES categories_produit(id) ON DELETE SET NULL,
  image_url     TEXT,
  disponible    BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (fabricant_id, reference)
);

CREATE INDEX idx_produits_fabricant ON produits(fabricant_id);
CREATE INDEX idx_produits_categorie ON produits(categorie_id);

CREATE TRIGGER trg_produits_updated_at
  BEFORE UPDATE ON produits
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Un point de vente peut être attribué à plusieurs fabricants, et un fabricant
-- couvre plusieurs points de vente : relation many-to-many portée par l'administrateur.
CREATE TABLE attributions_reseau (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  fabricant_id       UUID NOT NULL REFERENCES fabricants(id) ON DELETE CASCADE,
  point_de_vente_id  UUID NOT NULL REFERENCES points_de_vente(id) ON DELETE CASCADE,
  date_attribution   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (fabricant_id, point_de_vente_id)
);

CREATE INDEX idx_attributions_fabricant ON attributions_reseau(fabricant_id);
CREATE INDEX idx_attributions_point_de_vente ON attributions_reseau(point_de_vente_id);
