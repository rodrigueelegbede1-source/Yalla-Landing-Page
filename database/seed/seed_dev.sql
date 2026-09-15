-- seed_dev.sql
-- Données de démonstration reprenant les noms utilisés dans les maquettes
-- (Ivoire Boissons, Superette Akwaba, Koffi A., etc.) pour tester le schéma
-- de bout en bout, y compris le déclenchement automatique de rupture et,
-- depuis la migration 011, le routage vers le distributeur puis l'escalade.
-- À exécuter uniquement en environnement de développement.

DO $$
DECLARE
  v_admin_id UUID;
  v_agent_user_id UUID;
  v_agent_id UUID;
  v_fabricant_user_id UUID;
  v_fabricant_id UUID;
  v_distributeur_user_id UUID;
  v_distributeur_id UUID;
  v_distributeur_voisin_user_id UUID;
  v_distributeur_voisin_id UUID;
  v_livreur_user_id UUID;
  v_livreur_id UUID;
  v_pdv_id UUID;
  v_pdv_voisin_id UUID;
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
  INSERT INTO utilisateurs (nom, telephone, mot_de_passe_hash, role)
  VALUES ('Sori D.', '+2250788000000', 'change_me', 'agent_recenseur')
  RETURNING id INTO v_agent_user_id;

  INSERT INTO agents_recenseurs (utilisateur_id, secteur)
  VALUES (v_agent_user_id, 'Abidjan Sud')
  RETURNING id INTO v_agent_id;

  -- Fabricant
  INSERT INTO utilisateurs (nom, telephone, mot_de_passe_hash, role)
  VALUES ('Ivoire Boissons', '+2250700000002', 'change_me', 'fabricant')
  RETURNING id INTO v_fabricant_user_id;

  INSERT INTO fabricants (utilisateur_id, nom)
  VALUES (v_fabricant_user_id, 'Ivoire Boissons')
  RETURNING id INTO v_fabricant_id;

  -- Distributeur affilié : celui à qui les ruptures partent en premier.
  INSERT INTO utilisateurs (nom, telephone, mot_de_passe_hash, role)
  VALUES ('Distrib Cocody', '+2250700000003', 'change_me', 'distributeur')
  RETURNING id INTO v_distributeur_user_id;

  INSERT INTO distributeurs (utilisateur_id, fabricant_id, nom, telephone)
  VALUES (v_distributeur_user_id, v_fabricant_id, 'Distrib Cocody', '+2250700000003')
  RETURNING id INTO v_distributeur_id;

  -- Second distributeur de la même commune, qui porte la même marque. Il ne voit
  -- rien tant que la rupture n'a pas été escaladée : c'est lui qui rend le
  -- cercle élargi observable en développement.
  INSERT INTO utilisateurs (nom, telephone, mot_de_passe_hash, role)
  VALUES ('Sahel Distribution', '+2250700000004', 'change_me', 'distributeur')
  RETURNING id INTO v_distributeur_voisin_user_id;

  INSERT INTO distributeurs (utilisateur_id, fabricant_id, nom, telephone)
  VALUES (v_distributeur_voisin_user_id, v_fabricant_id, 'Sahel Distribution', '+2250700000004')
  RETURNING id INTO v_distributeur_voisin_id;

  -- Livreur, rattaché au distributeur et non plus au fabricant.
  INSERT INTO utilisateurs (nom, telephone, mot_de_passe_hash, role)
  VALUES ('Koffi A.', '+2250712000000', 'change_me', 'livreur')
  RETURNING id INTO v_livreur_user_id;

  INSERT INTO livreurs (utilisateur_id, distributeur_id, en_ligne)
  VALUES (v_livreur_user_id, v_distributeur_id, true)
  RETURNING id INTO v_livreur_id;

  -- Point de vente (Cocody — coordonnées approximatives)
  INSERT INTO points_de_vente (nom, type_activite, adresse, commune, ville, position, gerant_nom, telephone, statut, agent_recenseur_id)
  VALUES (
    'Superette Akwaba', 'superette', 'Rue des Jardins', 'Cocody', 'Abidjan',
    ST_SetSRID(ST_MakePoint(-3.9862, 5.3599), 4326)::geography,
    'Aya Kouassi', '+2250745000000', 'actif', v_agent_id
  )
  RETURNING id INTO v_pdv_id;

  -- Seconde boutique de Cocody, desservie par le distributeur voisin. C'est elle
  -- qui place Sahel Distribution « dans la commune » au sens de la vue d'accès.
  INSERT INTO points_de_vente (nom, type_activite, adresse, commune, ville, position, gerant_nom, telephone, statut, agent_recenseur_id)
  VALUES (
    'Kiosque Djeni', 'kiosque', 'Boulevard Latrille', 'Cocody', 'Abidjan',
    ST_SetSRID(ST_MakePoint(-3.9940, 5.3660), 4326)::geography,
    'Djeni T.', '+2250745000001', 'actif', v_agent_id
  )
  RETURNING id INTO v_pdv_voisin_id;

  -- Catalogue
  SELECT id INTO v_categorie_boissons FROM categories_produit WHERE nom = 'Boissons';

  INSERT INTO produits (fabricant_id, nom, reference, categorie_id)
  VALUES (v_fabricant_id, 'Jus Ivoire Mangue 1L', 'IB-204', v_categorie_boissons)
  RETURNING id INTO v_produit_jus_id;

  INSERT INTO produits (fabricant_id, nom, reference, categorie_id)
  VALUES (v_fabricant_id, 'Eau Ivoire 1,5L', 'IB-118', v_categorie_boissons)
  RETURNING id INTO v_produit_eau_id;

  -- Attributions : le fabricant couvre les deux boutiques, chacune par la main
  -- d'un distributeur différent. C'est ce triplet que lit le trigger de routage.
  INSERT INTO attributions_reseau (fabricant_id, point_de_vente_id, distributeur_id)
  VALUES (v_fabricant_id, v_pdv_id, v_distributeur_id);

  INSERT INTO attributions_reseau (fabricant_id, point_de_vente_id, distributeur_id)
  VALUES (v_fabricant_id, v_pdv_voisin_id, v_distributeur_voisin_id);

  -- Niveaux de stock initiaux
  INSERT INTO stocks (point_de_vente_id, produit_id, quantite) VALUES
    (v_pdv_id, v_produit_jus_id, 2),
    (v_pdv_id, v_produit_eau_id, 15);

  -- Une vente qui vide le stock de jus (quantite 2) : doit déclencher une rupture
  -- automatique, et le trigger de routage doit lui attribuer Distrib Cocody.
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
--
-- 1. La rupture automatique existe et a bien un destinataire :
-- SELECT statut, signalement_automatique, distributeur_id FROM ruptures;
--
-- 2. Seul le distributeur attribué la voit pour l'instant (1 ligne, cercle = attribue) :
-- SELECT * FROM v_acces_rupture_distributeur;
--
-- 3. Simulation de l'escalade sans attendre deux heures : on vieillit la rupture,
--    puis on déclenche une passe. La vue doit alors renvoyer 2 lignes, la seconde
--    au profit de Sahel Distribution avec cercle = elargi.
-- UPDATE ruptures SET date_signalement = now() - INTERVAL '3 hours';
-- SELECT * FROM escalader_ruptures_en_attente();
-- SELECT * FROM v_acces_rupture_distributeur;
--
-- 4. Péremption : on vieillit au-delà de 24 h et on repasse.
-- UPDATE ruptures SET date_signalement = now() - INTERVAL '30 hours';
-- SELECT * FROM escalader_ruptures_en_attente();
-- SELECT statut FROM ruptures;              -- non_servie
-- SELECT * FROM v_taux_de_service_par_fabricant;
