-- 010_utilisateur_point_de_vente.sql
-- Comble un trou du schéma initial : contrairement à fabricants, livreurs et
-- agents_recenseurs, points_de_vente n'avait pas de lien vers un compte de
-- connexion. Nécessaire pour que le rôle 'point_de_vente' (déjà présent dans
-- l'enum role_utilisateur) puisse réellement se connecter à sa propre fiche.

ALTER TABLE points_de_vente
  ADD COLUMN utilisateur_id UUID REFERENCES utilisateurs(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX uq_points_de_vente_utilisateur ON points_de_vente(utilisateur_id)
  WHERE utilisateur_id IS NOT NULL;

-- Le gérant (gerant_nom / telephone) reste tel quel pour les points de vente
-- enregistrés par un agent recenseur sans compte associé immédiat ; le compte
-- peut être créé et rattaché après coup lors de l'activation par l'administrateur.
