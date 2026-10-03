-- Retours terrain envoyés par les boutiques aux marques et distributeurs
-- qui les desservent. La caisse et les stocks ne sont pas requis.

CREATE TABLE retours_terrain (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  point_de_vente_id  UUID NOT NULL REFERENCES points_de_vente(id) ON DELETE CASCADE,
  destinataire_role  TEXT NOT NULL CHECK (destinataire_role IN ('fabricant', 'distributeur')),
  fabricant_id       UUID REFERENCES fabricants(id),
  distributeur_id    UUID REFERENCES distributeurs(id),
  produit_id         UUID REFERENCES produits(id) ON DELETE SET NULL,
  sujet              TEXT NOT NULL CHECK (sujet IN ('qualite', 'prix', 'disponibilite', 'livraison', 'publicite', 'autre')),
  message            TEXT NOT NULL CHECK (char_length(trim(message)) BETWEEN 5 AND 1200),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (
    (destinataire_role = 'fabricant' AND fabricant_id IS NOT NULL AND distributeur_id IS NULL)
    OR
    (destinataire_role = 'distributeur' AND distributeur_id IS NOT NULL AND fabricant_id IS NULL)
  )
);

CREATE INDEX idx_retours_terrain_boutique ON retours_terrain(point_de_vente_id, created_at DESC);
CREATE INDEX idx_retours_terrain_fabricant ON retours_terrain(fabricant_id, created_at DESC)
  WHERE fabricant_id IS NOT NULL;
CREATE INDEX idx_retours_terrain_distributeur ON retours_terrain(distributeur_id, created_at DESC)
  WHERE distributeur_id IS NOT NULL;

ALTER TABLE retours_terrain ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON retours_terrain TO authenticated;

CREATE POLICY retours_terrain_lecteurs ON retours_terrain
FOR SELECT TO authenticated
USING (
  (auth_role() = 'point_de_vente' AND point_de_vente_id = auth_id_metier())
  OR (auth_role() = 'fabricant' AND fabricant_id = auth_id_metier())
  OR (auth_role() = 'distributeur' AND distributeur_id = auth_id_metier())
);

CREATE POLICY pdv_retour_terrain_destinataire ON points_de_vente
FOR SELECT TO authenticated
USING (
  (auth_role() = 'fabricant' AND EXISTS (
    SELECT 1 FROM retours_terrain r
    WHERE r.point_de_vente_id = points_de_vente.id
      AND r.fabricant_id = auth_id_metier()
  ))
  OR (auth_role() = 'distributeur' AND EXISTS (
    SELECT 1 FROM retours_terrain r
    WHERE r.point_de_vente_id = points_de_vente.id
      AND r.distributeur_id = auth_id_metier()
  ))
);

-- Une boutique ne peut choisir que ses marques et ses distributeurs attribués.
CREATE POLICY distributeurs_des_boutiques ON distributeurs
FOR SELECT TO authenticated
USING (
  auth_role() = 'point_de_vente'
  AND EXISTS (
    SELECT 1 FROM attributions_reseau ar
    WHERE ar.distributeur_id = distributeurs.id
      AND ar.point_de_vente_id = auth_id_metier()
  )
);

CREATE VIEW v_destinataires_retours
WITH (security_invoker = on) AS
SELECT DISTINCT
  'fabricant'::TEXT AS destinataire_role,
  f.id AS destinataire_id,
  f.nom AS destinataire_nom
FROM attributions_reseau ar
JOIN fabricants f ON f.id = ar.fabricant_id
JOIN produits p ON p.fabricant_id = f.id AND p.disponible
WHERE auth_role() = 'point_de_vente'
  AND ar.point_de_vente_id = auth_id_metier()

UNION

SELECT DISTINCT
  'distributeur'::TEXT,
  d.id,
  d.nom
FROM attributions_reseau ar
JOIN distributeurs d ON d.id = ar.distributeur_id
WHERE auth_role() = 'point_de_vente'
  AND ar.point_de_vente_id = auth_id_metier()
  AND ar.distributeur_id IS NOT NULL;

CREATE VIEW v_mes_retours_terrain
WITH (security_invoker = on) AS
SELECT
  r.id AS retour_id,
  r.destinataire_role,
  COALESCE(f.nom, d.nom) AS destinataire,
  p.nom AS produit,
  r.sujet,
  r.message,
  r.created_at
FROM retours_terrain r
LEFT JOIN fabricants f ON f.id = r.fabricant_id
LEFT JOIN distributeurs d ON d.id = r.distributeur_id
LEFT JOIN produits p ON p.id = r.produit_id
WHERE auth_role() = 'point_de_vente'
  AND r.point_de_vente_id = auth_id_metier();

CREATE VIEW v_produits_retour_distributeur
WITH (security_invoker = on) AS
SELECT DISTINCT
  ar.distributeur_id,
  p.id AS produit_id,
  p.fabricant_id,
  p.nom AS produit_nom
FROM attributions_reseau ar
JOIN produits p ON p.fabricant_id = ar.fabricant_id AND p.disponible
WHERE auth_role() = 'point_de_vente'
  AND ar.point_de_vente_id = auth_id_metier()
  AND ar.distributeur_id IS NOT NULL;

CREATE VIEW v_retours_terrain_recus
WITH (security_invoker = on) AS
SELECT
  r.id AS retour_id,
  r.destinataire_role,
  pdv.nom AS point_de_vente,
  pdv.commune,
  p.nom AS produit,
  r.sujet,
  r.message,
  r.created_at
FROM retours_terrain r
JOIN points_de_vente pdv ON pdv.id = r.point_de_vente_id
LEFT JOIN produits p ON p.id = r.produit_id
WHERE (auth_role() = 'fabricant' AND r.fabricant_id = auth_id_metier())
   OR (auth_role() = 'distributeur' AND r.distributeur_id = auth_id_metier());

GRANT SELECT ON v_destinataires_retours, v_mes_retours_terrain,
  v_produits_retour_distributeur, v_retours_terrain_recus TO authenticated;

CREATE OR REPLACE FUNCTION envoyer_retour_terrain(
  p_destinataire_role TEXT,
  p_destinataire_id   UUID,
  p_produit_id        UUID,
  p_sujet             TEXT,
  p_message           TEXT
)
RETURNS retours_terrain
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_point_de_vente_id UUID := auth_id_metier();
  v_fabricant_id UUID;
  v_retour retours_terrain;
  v_sujet TEXT := lower(trim(COALESCE(p_sujet, '')));
  v_message TEXT := trim(COALESCE(p_message, ''));
BEGIN
  IF auth_role() <> 'point_de_vente' THEN
    RAISE EXCEPTION 'Seul un point de vente peut envoyer un retour terrain'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_point_de_vente_id IS NULL THEN
    RAISE EXCEPTION 'Boutique introuvable' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_sujet NOT IN ('qualite', 'prix', 'disponibilite', 'livraison', 'publicite', 'autre') THEN
    RAISE EXCEPTION 'Sujet de retour invalide' USING ERRCODE = 'check_violation';
  END IF;
  IF char_length(v_message) NOT BETWEEN 5 AND 1200 THEN
    RAISE EXCEPTION 'Le retour doit contenir entre 5 et 1200 caractères'
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_destinataire_role = 'fabricant' THEN
    IF p_destinataire_id IS NULL THEN
      RAISE EXCEPTION 'Choisissez un fabricant destinataire'
        USING ERRCODE = 'check_violation';
    END IF;
    IF p_produit_id IS NULL THEN
      RAISE EXCEPTION 'Choisissez un produit de ce fabricant'
        USING ERRCODE = 'check_violation';
    END IF;

    SELECT p.fabricant_id INTO v_fabricant_id
    FROM produits p
    WHERE p.id = p_produit_id
      AND p.disponible
      AND EXISTS (
        SELECT 1 FROM attributions_reseau ar
        WHERE ar.point_de_vente_id = v_point_de_vente_id
          AND ar.fabricant_id = p.fabricant_id
      );

    IF v_fabricant_id IS NULL OR v_fabricant_id <> p_destinataire_id THEN
      RAISE EXCEPTION 'Ce produit ne relève pas de ce fabricant ou de votre boutique'
        USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO retours_terrain (
      point_de_vente_id, destinataire_role, fabricant_id, produit_id, sujet, message
    ) VALUES (
      v_point_de_vente_id, 'fabricant', v_fabricant_id, p_produit_id, v_sujet, v_message
    ) RETURNING * INTO v_retour;

  ELSIF p_destinataire_role = 'distributeur' THEN
    IF NOT EXISTS (
      SELECT 1 FROM attributions_reseau ar
      WHERE ar.point_de_vente_id = v_point_de_vente_id
        AND ar.distributeur_id = p_destinataire_id
        AND (p_produit_id IS NULL OR EXISTS (
          SELECT 1 FROM produits p
          WHERE p.id = p_produit_id
            AND p.disponible
            AND p.fabricant_id = ar.fabricant_id
        ))
    ) THEN
      RAISE EXCEPTION 'Ce distributeur ne dessert pas votre boutique pour ce produit'
        USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO retours_terrain (
      point_de_vente_id, destinataire_role, distributeur_id, produit_id, sujet, message
    ) VALUES (
      v_point_de_vente_id, 'distributeur', p_destinataire_id, p_produit_id, v_sujet, v_message
    ) RETURNING * INTO v_retour;

  ELSE
    RAISE EXCEPTION 'Destinataire invalide' USING ERRCODE = 'check_violation';
  END IF;

  RETURN v_retour;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION envoyer_retour_terrain(TEXT, UUID, UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION envoyer_retour_terrain(TEXT, UUID, UUID, TEXT, TEXT) TO authenticated;

COMMENT ON TABLE retours_terrain IS
  'Retours textuels des boutiques, adressés à leurs fabricants ou distributeurs attribués. Sans accès aux ventes ni aux stocks.';
COMMENT ON VIEW v_retours_terrain_recus IS
  'Retours visibles du seul fabricant ou distributeur désigné, selon l''identité signée.';