-- Accès lecture du fabricant à son propre réseau catalogue.
-- Les vues fabricant sont security_invoker : sans ces politiques, elles sont
-- correctement sécurisées mais rendent des listes vides.

CREATE POLICY pdv_fabricant_son_catalogue ON points_de_vente
FOR SELECT TO authenticated
USING (
  auth_role() = 'fabricant'
  AND EXISTS (
    SELECT 1 FROM attributions_reseau ar
    WHERE ar.point_de_vente_id = points_de_vente.id
      AND ar.fabricant_id = auth_id_metier()
  )
);

CREATE POLICY ruptures_fabricant_son_catalogue ON ruptures
FOR SELECT TO authenticated
USING (
  auth_role() = 'fabricant'
  AND EXISTS (
    SELECT 1 FROM produits p
    WHERE p.id = ruptures.produit_id
      AND p.fabricant_id = auth_id_metier()
  )
);

CREATE POLICY distributeurs_fabricant_son_catalogue ON distributeurs
FOR SELECT TO authenticated
USING (
  auth_role() = 'fabricant'
  AND (
    fabricant_id = auth_id_metier()
    OR EXISTS (
      SELECT 1 FROM attributions_reseau ar
      WHERE ar.distributeur_id = distributeurs.id
        AND ar.fabricant_id = auth_id_metier()
    )
  )
);
