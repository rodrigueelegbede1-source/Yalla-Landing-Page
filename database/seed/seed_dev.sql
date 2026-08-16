-- seed_dev.sql
-- Données de démonstration reprenant les noms utilisés dans les 5 maquettes
-- (Ivoire Boissons, Superette Akwaba, Koffi A., etc.) pour tester le schéma
-- de bout en bout, y compris le déclenchement automatique de rupture.
-- À exécuter uniquement en environnement de développement.

DO $$
DECLARE
  v_admin_id UUID;
  v_agent_user_id UUID;
  v_agent_id UUID;
  v_fabricant_user_id UUID;
  v_fabricant_id UUID;
  v_livreur_user_id UUID;
  v_livreur_id UUID;
  v_pdv_id UUID;
  v_categorie_boissons UUID;
  v_produit_jus_id UUID;
  v_produit_eau_id UUID;
  v_vente_id UUID;
BEGIN
  -- Administrateur
  INSERT INTO utilisateurs (nom, telephone, email, mot_de_passe_hash, role)
  VALUES ('Elegson Admin', '+2250700000001', 'admin@yalla.ci', 'change_me', 'administrateur')
  RETURNING id INTO v_admin_id;

  -- Agent recenseur
  INSERT INTO utilisateurs (nom, telephone, role)
  VALUES ('Sori D.', '+2250788000000', 'agent_recenseur')
  RETURNING id INTO v_agent_user_id;

  INSERT INTO agents_recenseurs (utilisateur_id, secteur)
  VALUES (v_agent_user_id, 'Abidjan Sud')
  RETURNING id INTO v_agent_id;

  -- Fabricant
  INSERT INTO utilisateurs (nom, telephone, role)
  VALUES ('Ivoire Boissons', '+2250700000002', 'fabricant')
  RETURNING id INTO v_fabricant_user_id;

  INSERT INTO fabricants (utilisateur_id, nom)
  VALUES (v_fabricant_user_id, 'Ivoire Boissons')
  RETURNING id INTO v_fabricant_id;

  -- Livreur affilié
  INSERT INTO utilisateurs (nom, telephone, role)
  VALUES ('Koffi A.', '+2250712000000', 'livreur')
  RETURNING id INTO v_livreur_user_id;

  INSERT INTO livreurs (utilisateur_id, fabricant_id, en_ligne)
  VALUES (v_livreur_user_id, v_fabricant_id, true)
  RETURNING id INTO v_livreur_id;

  -- Point de vente (Cocody — coordonnées approximatives)
  INSERT INTO points_de_vente (nom, type_activite, adresse, commune, ville, position, gerant_nom, telephone, statut, agent_recenseur_id)
  VALUES (
    'Superette Akwaba', 'superette', 'Rue des Jardins', 'Cocody', 'Abidjan',
    ST_SetSRID(ST_MakePoint(-3.9862, 5.3599), 4326)::geography,
    'Aya Kouassi', '+2250745000000', 'actif', v_agent_id
  )
  RETURNING id INTO v_pdv_id;

  -- Catalogue
  SELECT id INTO v_categorie_boissons FROM categories_produit WHERE nom = 'Boissons';

  INSERT INTO produits (fabricant_id, nom, reference, categorie_id)
  VALUES (v_fabricant_id, 'Jus Ivoire Mangue 1L', 'IB-204', v_categorie_boissons)
  RETURNING id INTO v_produit_jus_id;

  INSERT INTO produits (fabricant_id, nom, reference, categorie_id)
  VALUES (v_fabricant_id, 'Eau Ivoire 1,5L', 'IB-118', v_categorie_boissons)
  RETURNING id INTO v_produit_eau_id;

  -- Attribution du point de vente au fabricant
  INSERT INTO attributions_reseau (fabricant_id, point_de_vente_id)
  VALUES (v_fabricant_id, v_pdv_id);

  -- Niveaux de stock initiaux
  INSERT INTO stocks (point_de_vente_id, produit_id, quantite) VALUES
    (v_pdv_id, v_produit_jus_id, 2),
    (v_pdv_id, v_produit_eau_id, 15);

  -- Une vente qui vide le stock de jus (quantite 2) : doit déclencher une rupture automatique.
  INSERT INTO ventes (point_de_vente_id, montant_total)
  VALUES (v_pdv_id, 2400)
  RETURNING id INTO v_vente_id;

  INSERT INTO lignes_vente (vente_id, produit_id, quantite, prix_unitaire)
  VALUES (v_vente_id, v_produit_jus_id, 2, 1200);

  -- Une position pour le livreur, pour tester la carte / le tri par proximité.
  INSERT INTO positions_livreurs (livreur_id, position)
  VALUES (v_livreur_id, ST_SetSRID(ST_MakePoint(-3.9800, 5.3550), 4326)::geography);

END $$;

-- Vérifications rapides après exécution :
-- SELECT * FROM ruptures;                    -- doit contenir 1 ligne, signalement_automatique = true
-- SELECT * FROM v_ruptures_ouvertes;
-- SELECT * FROM stocks WHERE quantite <= 0;
