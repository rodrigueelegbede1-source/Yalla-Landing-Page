-- Une coupure après validation serveur ne doit jamais créer une seconde vente.
-- La clé est créée par le téléphone avant le premier envoi et réutilisée lors
-- des retries. L'unicité est limitée au point de vente pour ne pas imposer une
-- coordination entre appareils différents.

ALTER TABLE ventes
  ADD COLUMN cle_operation UUID;

CREATE UNIQUE INDEX uq_ventes_point_cle_operation
  ON ventes(point_de_vente_id, cle_operation)
  WHERE cle_operation IS NOT NULL;

DROP FUNCTION IF EXISTS enregistrer_vente(JSONB);

CREATE OR REPLACE FUNCTION enregistrer_vente(
  p_lignes JSONB,
  p_cle_operation UUID
)
RETURNS ventes
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_pdv_id UUID := auth_id_metier();
  v_vente  ventes;
  v_total  NUMERIC(12,2);
  v_ligne  JSONB;
BEGIN
  IF auth_role() <> 'point_de_vente' THEN
    RAISE EXCEPTION 'Seul un point de vente peut encaisser' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_cle_operation IS NULL THEN
    RAISE EXCEPTION 'La clé d''opération est obligatoire' USING ERRCODE = 'null_value_not_allowed';
  END IF;

  SELECT * INTO v_vente
  FROM ventes
  WHERE point_de_vente_id = v_pdv_id
    AND cle_operation = p_cle_operation;

  IF v_vente.id IS NOT NULL THEN
    RETURN v_vente;
  END IF;

  IF p_lignes IS NULL OR jsonb_array_length(p_lignes) = 0 THEN
    RAISE EXCEPTION 'Une vente sans ligne n''a pas de sens' USING ERRCODE = 'check_violation';
  END IF;

  SELECT COALESCE(SUM((l->>'quantite')::INTEGER * (l->>'prix_unitaire')::NUMERIC), 0)
    INTO v_total
    FROM jsonb_array_elements(p_lignes) l;

  INSERT INTO ventes (point_de_vente_id, montant_total, cle_operation)
  VALUES (v_pdv_id, v_total, p_cle_operation)
  RETURNING * INTO v_vente;

  FOR v_ligne IN SELECT * FROM jsonb_array_elements(p_lignes) LOOP
    INSERT INTO lignes_vente (vente_id, produit_id, produit_libre_nom, quantite, prix_unitaire)
    VALUES (
      v_vente.id,
      NULLIF(v_ligne->>'produit_id', '')::UUID,
      NULLIF(v_ligne->>'produit_libre_nom', ''),
      (v_ligne->>'quantite')::INTEGER,
      (v_ligne->>'prix_unitaire')::NUMERIC
    );
  END LOOP;

  RETURN v_vente;
EXCEPTION
  WHEN unique_violation THEN
    -- Deux tentatives concurrentes avec la même clé renvoient la vente gagnante.
    SELECT * INTO v_vente
    FROM ventes
    WHERE point_de_vente_id = v_pdv_id
      AND cle_operation = p_cle_operation;
    IF v_vente.id IS NOT NULL THEN
      RETURN v_vente;
    END IF;
    RAISE;
END;
$fn$;

COMMENT ON COLUMN ventes.cle_operation IS
  'Clé idempotente fournie par le téléphone pour éviter les doubles encaissements';

REVOKE EXECUTE ON FUNCTION enregistrer_vente(JSONB, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION enregistrer_vente(JSONB, UUID) TO authenticated;

-- Compatibilité avec une ancienne APK déjà installée. Elle ne connaît pas la
-- clé idempotente, mais doit continuer à encaisser après la migration. Les
-- nouvelles versions appellent exclusivement la signature à deux paramètres.
CREATE OR REPLACE FUNCTION enregistrer_vente(p_lignes JSONB)
RETURNS ventes
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  RETURN enregistrer_vente(p_lignes, gen_random_uuid());
END;
$fn$;

REVOKE EXECUTE ON FUNCTION enregistrer_vente(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION enregistrer_vente(JSONB) TO authenticated;
