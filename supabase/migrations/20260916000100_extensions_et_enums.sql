-- 001_extensions_et_enums.sql
-- Extensions PostgreSQL nécessaires + types énumérés partagés par tout le schéma Yalla.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "postgis";    -- types et fonctions géospatiales

-- Rôles applicatifs (un utilisateur = un rôle)
CREATE TYPE role_utilisateur AS ENUM (
  'administrateur',
  'fabricant',
  'livreur',
  'point_de_vente',
  'agent_recenseur'
);

CREATE TYPE type_activite AS ENUM (
  'superette',
  'boutique',
  'kiosque',
  'restaurant_maquis'
);

CREATE TYPE statut_point_de_vente AS ENUM (
  'actif',
  'en_attente_activation',
  'retire'
);

CREATE TYPE statut_fabricant AS ENUM (
  'actif',
  'suspendu'
);

CREATE TYPE statut_rupture AS ENUM (
  'signalee',
  'prise_en_charge',
  'resolue'
);

CREATE TYPE statut_livraison AS ENUM (
  'en_cours',
  'terminee',
  'annulee'
);

CREATE TYPE statut_transaction AS ENUM (
  'en_attente',
  'confirmee',
  'echouee'
);

CREATE TYPE fournisseur_paiement AS ENUM (
  'orange_ci',
  'mtn_ci',
  'wave',
  'moov',
  'djamo'
);

CREATE TYPE type_notification AS ENUM (
  'notification',
  'splash_publicitaire',
  'sondage'
);

CREATE TYPE cible_notification AS ENUM (
  'reseau_complet',
  'fabricants',
  'points_de_vente',
  'livreurs'
);

-- Fonction générique utilisée par tous les triggers "updated_at" des tables suivantes.
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
