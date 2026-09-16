-- seed.sql — données de démonstration, environnement de développement uniquement.
--
-- Appliqué automatiquement par `supabase db reset`.
--
-- Différence avec l'ancien seed : plus de `mot_de_passe_hash`. Supabase Auth
-- détient les identifiants, et les lignes `utilisateurs` sont créées ici SANS
-- `auth_user_id`. C'est volontaire et c'est le cas nominal : sur le terrain,
-- l'agent recenseur enregistre une boutique avant que son gérant n'ait un
-- compte. Le rattachement se fait ensuite par `rattacher_compte_auth()`.
--
-- Pour ouvrir de vrais comptes de test, voir supabase/README.md.
--
-- Le réseau simulé est volontairement minimal mais complet : il suffit à
-- dérouler la boucle entière, de la vente à la livraison, et à observer
-- l'escalade entre deux distributeurs concurrents de la même commune.

DO $$
DECLARE
  v_admin_id                UUID;
  v_agent_user_id           UUID;
  v_agent_id                UUID;
  v_fab_user_id             UUID;
  v_fab_id                  UUID;
  v_dist_user_id            UUID;
  v_dist_id                 UUID;
  v_dist_voisin_user_id     UUID;
  v_dist_voisin_id          UUID;
  v_livreur_user_id         UUID;
  v_livreur_id              UUID;
  v_pdv_user_id             UUID;
  v_pdv_id                  UUID;
  v_pdv_voisin_id           UUID;
  v_cat_boissons            UUID;
  v_produit_jus_id          UUID;
  v_produit_eau_id          UUID;
  v_vente_id                UUID;
BEGIN
  -- ── Administrateur ───────────────────────────────────────────────────────
  INSERT INTO utilisateurs (nom, telephone, email, role)
  VALUES ('Elegson Admin', '+2250700000001', 'admin@yalla.ci', 'administrateur')
  RETURNING id INTO v_admin_id;

  -- ── Agent recenseur ──────────────────────────────────────────────────────
  INSERT INTO utilisateurs (nom, telephone, role)
  VALUES ('Sori D.', '+2250788000000', 'agent_recenseur')
  RETURNING id INTO v_agent_user_id;

  INSERT INTO agents_recenseurs (utilisateur_id, secteur)
  VALUES (v_agent_user_id, 'Abidjan Sud')
  RETURNING id INTO v_agent_id;

  -- ── Fabricant ────────────────────────────────────────────────────────────
  INSERT INTO utilisateurs (nom, telephone, role)
  VALUES ('Ivoire Boissons', '+2250700000002', 'fabricant')
  RETURNING id INTO v_fab_user_id;

  INSERT INTO fabricants (utilisateur_id, nom)
  VALUES (v_fab_user_id, 'Ivoire Boissons')
  RETURNING id INTO v_fab_id;

  -- ── Distributeur attribué ────────────────────────────────────────────────
  INSERT INTO utilisateurs (nom, telephone, role)
  VALUES ('Distrib Cocody', '+2250700000003', 'distributeur')
  RETURNING id INTO v_dist_user_id;

  INSERT INTO distributeurs (utilisateur_id, fabricant_id, nom, telephone)
  VALUES (v_dist_user_id, v_fab_id, 'Distrib Cocody', '+2250700000003')
  RETURNING id INTO v_dist_id;

  -- ── Distributeur voisin ──────────────────────────────────────────────────
  -- Même commune, même marque. Il ne voit rien tant que la rupture n'a pas
  -- été escaladée : c'est lui qui rend le cercle élargi observable.
  INSERT INTO utilisateurs (nom, telephone, role)
  VALUES ('Sahel Distribution', '+2250700000004', 'distributeur')
  RETURNING id INTO v_dist_voisin_user_id;

  INSERT INTO distributeurs (utilisateur_id, fabricant_id, nom, telephone)
  VALUES (v_dist_voisin_user_id, v_fab_id, 'Sahel Distribution', '+2250700000004')
  RETURNING id INTO v_dist_voisin_id;

  -- ── Livreur ──────────────────────────────────────────────────────────────
  INSERT INTO utilisateurs (nom, telephone, role)
  VALUES ('Koffi A.', '+2250712000000', 'livreur')
  RETURNING id INTO v_livreur_user_id;

  INSERT INTO livreurs (utilisateur_id, distributeur_id, en_ligne)
  VALUES (v_livreur_user_id, v_dist_id, true)
  RETURNING id INTO v_livreur_id;

  -- ── Points de vente ──────────────────────────────────────────────────────
  -- Le gérant a son propre compte : c'est la migration 010 qui a comblé ce trou.
  INSERT INTO utilisateurs (nom, telephone, role)
  VALUES ('Aya Kouassi', '+2250745000000', 'point_de_vente')
  RETURNING id INTO v_pdv_user_id;

  INSERT INTO points_de_vente (nom, type_activite, adresse, commune, ville, position,
                               gerant_nom, telephone, statut, agent_recenseur_id, utilisateur_id)
  VALUES ('Superette Akwaba', 'superette', 'Rue des Jardins', 'Cocody', 'Abidjan',
          ST_SetSRID(ST_MakePoint(-3.9862, 5.3599), 4326)::geography,
          'Aya Kouassi', '+2250745000000', 'actif', v_agent_id, v_pdv_user_id)
  RETURNING id INTO v_pdv_id;

  -- Seconde boutique de Cocody, desservie par le distributeur voisin. C'est
  -- elle qui place Sahel Distribution « dans la commune » au sens du cercle élargi.
  INSERT INTO points_de_vente (nom, type_activite, adresse, commune, ville, position,
                               gerant_nom, telephone, statut, agent_recenseur_id)
  VALUES ('Kiosque Djeni', 'kiosque', 'Boulevard Latrille', 'Cocody', 'Abidjan',
          ST_SetSRID(ST_MakePoint(-3.9940, 5.3660), 4326)::geography,
          'Djeni T.', '+2250745000001', 'actif', v_agent_id)
  RETURNING id INTO v_pdv_voisin_id;

  -- ── Catalogue ────────────────────────────────────────────────────────────
  SELECT id INTO v_cat_boissons FROM categories_produit WHERE nom = 'Boissons';

  INSERT INTO produits (fabricant_id, nom, reference, categorie_id)
  VALUES (v_fab_id, 'Jus Ivoire Mangue 1L', 'IB-204', v_cat_boissons)
  RETURNING id INTO v_produit_jus_id;

  INSERT INTO produits (fabricant_id, nom, reference, categorie_id)
  VALUES (v_fab_id, 'Eau Ivoire 1,5L', 'IB-118', v_cat_boissons)
  RETURNING id INTO v_produit_eau_id;

  -- ── Attributions ─────────────────────────────────────────────────────────
  -- Le triplet fabricant / boutique / distributeur. C'est LA colonne que
  -- l'ancien backend ne renseignait jamais, ce qui laissait toute rupture sans
  -- destinataire et rendait le routage inopérant.
  INSERT INTO attributions_reseau (fabricant_id, point_de_vente_id, distributeur_id)
  VALUES (v_fab_id, v_pdv_id, v_dist_id);

  INSERT INTO attributions_reseau (fabricant_id, point_de_vente_id, distributeur_id)
  VALUES (v_fab_id, v_pdv_voisin_id, v_dist_voisin_id);

  -- ── Stocks ───────────────────────────────────────────────────────────────
  -- Sans ligne de stock suivie, le trigger de caisse sort sans rien faire et
  -- aucune rupture automatique ne peut naître.
  INSERT INTO stocks (point_de_vente_id, produit_id, quantite) VALUES
    (v_pdv_id, v_produit_jus_id, 2),
    (v_pdv_id, v_produit_eau_id, 15);

  -- ── La vente qui déclenche tout ──────────────────────────────────────────
  -- Deux jus vendus sur un stock de deux : le stock tombe à zéro, le trigger
  -- crée la rupture, et le trigger de routage lui attribue Distrib Cocody.
  INSERT INTO ventes (point_de_vente_id, montant_total)
  VALUES (v_pdv_id, 2400)
  RETURNING id INTO v_vente_id;

  INSERT INTO lignes_vente (vente_id, produit_id, quantite, prix_unitaire)
  VALUES (v_vente_id, v_produit_jus_id, 2, 1200);

  -- ── Position du livreur ──────────────────────────────────────────────────
  INSERT INTO positions_livreurs (livreur_id, position)
  VALUES (v_livreur_id, ST_SetSRID(ST_MakePoint(-3.9800, 5.3550), 4326)::geography);
END $$;

-- Vérifications rapides :
--
--   SELECT statut, signalement_automatique, distributeur_id FROM ruptures;
--   SELECT * FROM v_acces_rupture_distributeur;   -- 1 ligne, cercle = attribue
--
--   UPDATE ruptures SET date_signalement = now() - INTERVAL '3 hours';
--   SELECT * FROM escalader_ruptures_en_attente();
--   SELECT * FROM v_acces_rupture_distributeur;   -- 2 lignes, la 2e en elargi
