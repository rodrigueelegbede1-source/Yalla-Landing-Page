-- 005_ruptures_et_livraisons.sql

CREATE TABLE ruptures (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  point_de_vente_id        UUID NOT NULL REFERENCES points_de_vente(id) ON DELETE CASCADE,
  produit_id               UUID NOT NULL REFERENCES produits(id) ON DELETE CASCADE,
  quantite_demandee        INTEGER,
  statut                   statut_rupture NOT NULL DEFAULT 'signalee',
  signalement_automatique  BOOLEAN NOT NULL DEFAULT false,
  date_signalement         TIMESTAMPTZ NOT NULL DEFAULT now(),
  date_resolution          TIMESTAMPTZ,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ruptures_point_de_vente ON ruptures(point_de_vente_id);
CREATE INDEX idx_ruptures_produit ON ruptures(produit_id);
CREATE INDEX idx_ruptures_statut ON ruptures(statut);
-- Le fabricant concerné se déduit de produits.fabricant_id : cet index accélère
-- "toutes les ruptures ouvertes sur mon catalogue" (jointure ruptures -> produits).
CREATE INDEX idx_ruptures_statut_produit ON ruptures(statut, produit_id);

CREATE TRIGGER trg_ruptures_updated_at
  BEFORE UPDATE ON ruptures
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE livraisons (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rupture_id         UUID REFERENCES ruptures(id) ON DELETE SET NULL,
  livreur_id         UUID NOT NULL REFERENCES livreurs(id) ON DELETE RESTRICT,
  point_de_vente_id  UUID NOT NULL REFERENCES points_de_vente(id) ON DELETE RESTRICT,
  statut             statut_livraison NOT NULL DEFAULT 'en_cours',
  date_debut         TIMESTAMPTZ NOT NULL DEFAULT now(),
  date_fin           TIMESTAMPTZ,
  montant            NUMERIC(12,2) NOT NULL DEFAULT 0,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_livraisons_livreur ON livraisons(livreur_id);
CREATE INDEX idx_livraisons_point_de_vente ON livraisons(point_de_vente_id);
CREATE INDEX idx_livraisons_rupture ON livraisons(rupture_id);
CREATE INDEX idx_livraisons_statut ON livraisons(statut);

CREATE TRIGGER trg_livraisons_updated_at
  BEFORE UPDATE ON livraisons
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Quand une livraison passe à "terminee", on marque la rupture d'origine comme résolue.
CREATE OR REPLACE FUNCTION resoudre_rupture_a_la_livraison()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.statut = 'terminee' AND NEW.rupture_id IS NOT NULL AND
     (OLD.statut IS DISTINCT FROM NEW.statut) THEN
    UPDATE ruptures
    SET statut = 'resolue',
        date_resolution = now()
    WHERE id = NEW.rupture_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_livraisons_resout_rupture
  AFTER UPDATE ON livraisons
  FOR EACH ROW EXECUTE FUNCTION resoudre_rupture_a_la_livraison();
