-- 20260916003900_paiement_especes.sql
--
-- L'énumération `fournisseur_paiement` ne listait que les opérateurs de paiement
-- mobile ivoiriens (Orange, MTN, Wave, Moov, Djamo), parce que le schéma a été
-- écrit en visant l'intégration CinetPay.
--
-- Or le MVP encaisse en espèces, et CinetPay est hors périmètre : compte
-- marchand à homologuer, webhooks à sécuriser, tests de bout en bout. Plusieurs
-- semaines pour une échéance qui en compte dix.
--
-- Sans cette valeur, `terminer_livraison()` ne pourrait tracer aucun règlement,
-- et on perdrait la mesure du chiffre d'affaires généré, qui est précisément
-- l'argument à montrer aux fabricants.
--
-- Migration isolée à dessein : PostgreSQL interdit d'utiliser une valeur
-- d'énumération dans la même transaction que son ajout.

ALTER TYPE fournisseur_paiement ADD VALUE IF NOT EXISTS 'especes';
