-- 006_caisse_enregistreuse.sql
-- Module caisse (type Loyverse). Un point de vente peut vendre des produits hors
-- catalogue Yalla : produit_id est alors NULL et produit_libre_nom porte le nom saisi.

CREATE TABLE stocks (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  point_de_vente_id   UUID NOT NULL REFERENCES points_de_vente(id) ON DELETE CASCADE,
  produit_id          UUID REFERENCES produits(id) ON DELETE CASCADE,
  produit_libre_nom   TEXT,
  quantite            INTEGER NOT NULL DEFAULT 0,
  date_maj            TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_stocks_produit_ou_libre CHECK (
    (produit_id IS NOT NULL AND produit_libre_nom IS NULL) OR
    (produit_id IS NULL AND produit_libre_nom IS NOT NULL)
  )
);

-- Un seul niveau de stock par produit catalogue et par point de vente.
CREATE UNIQUE INDEX uq_stocks_point_produit
  ON stocks(point_de_vente_id, produit_id)
  WHERE produit_id IS NOT NULL;

CREATE INDEX idx_stocks_point_de_vente ON stocks(point_de_vente_id);
CREATE INDEX idx_stocks_produit ON stocks(produit_id);

CREATE TABLE ventes (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  point_de_vente_id  UUID NOT NULL REFERENCES points_de_vente(id) ON DELETE CASCADE,
  date_vente         TIMESTAMPTZ NOT NULL DEFAULT now(),
  montant_total      NUMERIC(12,2) NOT NULL DEFAULT 0
);

CREATE INDEX idx_ventes_point_de_vente ON ventes(point_de_vente_id, date_vente DESC);

CREATE TABLE lignes_vente (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vente_id           UUID NOT NULL REFERENCES ventes(id) ON DELETE CASCADE,
  produit_id         UUID REFERENCES produits(id) ON DELETE RESTRICT,
  produit_libre_nom  TEXT,
  quantite           INTEGER NOT NULL CHECK (quantite > 0),
  prix_unitaire      NUMERIC(12,2) NOT NULL,
  CONSTRAINT chk_lignes_vente_produit_ou_libre CHECK (
    (produit_id IS NOT NULL AND produit_libre_nom IS NULL) OR
    (produit_id IS NULL AND produit_libre_nom IS NOT NULL)
  )
);

CREATE INDEX idx_lignes_vente_vente ON lignes_vente(vente_id);
CREATE INDEX idx_lignes_vente_produit ON lignes_vente(produit_id);

-- Règle métier : chaque ligne de vente décrémente le stock du produit catalogue
-- correspondant sur ce point de vente. Si le stock tombe à 0 (ou moins), une
-- rupture est créée automatiquement, sauf s'il en existe déjà une ouverte pour
-- ce produit sur ce point de vente. Les lignes hors catalogue (produit_id NULL)
-- ne touchent ni stocks ni ruptures.
CREATE OR REPLACE FUNCTION decrementer_stock_et_signaler_rupture()
RETURNS TRIGGER AS $$
DECLARE
  v_point_de_vente_id UUID;
  v_nouvelle_quantite INTEGER;
  v_rupture_ouverte_existe BOOLEAN;
BEGIN
  IF NEW.produit_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT point_de_vente_id INTO v_point_de_vente_id
  FROM ventes WHERE id = NEW.vente_id;

  UPDATE stocks
  SET quantite = quantite - NEW.quantite,
      date_maj = now()
  WHERE point_de_vente_id = v_point_de_vente_id
    AND produit_id = NEW.produit_id
  RETURNING quantite INTO v_nouvelle_quantite;

  -- Pas de ligne de stock suivie pour ce produit sur ce point de vente : rien à faire.
  IF v_nouvelle_quantite IS NULL THEN
    RETURN NEW;
  END IF;

  IF v_nouvelle_quantite <= 0 THEN
    SELECT EXISTS (
      SELECT 1 FROM ruptures
      WHERE point_de_vente_id = v_point_de_vente_id
        AND produit_id = NEW.produit_id
        AND statut IN ('signalee', 'prise_en_charge')
    ) INTO v_rupture_ouverte_existe;

    IF NOT v_rupture_ouverte_existe THEN
      INSERT INTO ruptures (point_de_vente_id, produit_id, statut, signalement_automatique)
      VALUES (v_point_de_vente_id, NEW.produit_id, 'signalee', true);
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_lignes_vente_decremente_stock
  AFTER INSERT ON lignes_vente
  FOR EACH ROW EXECUTE FUNCTION decrementer_stock_et_signaler_rupture();
