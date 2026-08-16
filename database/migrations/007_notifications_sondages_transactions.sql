-- 007_notifications_sondages_transactions.sql

CREATE TABLE notifications (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  emetteur_id  UUID NOT NULL REFERENCES utilisateurs(id) ON DELETE CASCADE,
  type         type_notification NOT NULL DEFAULT 'notification',
  titre        TEXT NOT NULL,
  message      TEXT NOT NULL,
  cible        cible_notification NOT NULL DEFAULT 'reseau_complet',
  date_envoi   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_notifications_emetteur ON notifications(emetteur_id);
CREATE INDEX idx_notifications_cible ON notifications(cible);

-- Options possibles pour une notification de type "sondage" (une ligne par option).
CREATE TABLE sondage_options (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id  UUID NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
  libelle          TEXT NOT NULL
);

CREATE INDEX idx_sondage_options_notification ON sondage_options(notification_id);

CREATE TABLE sondage_reponses (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id    UUID NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
  point_de_vente_id  UUID NOT NULL REFERENCES points_de_vente(id) ON DELETE CASCADE,
  option_choisie_id  UUID NOT NULL REFERENCES sondage_options(id) ON DELETE CASCADE,
  date_reponse       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (notification_id, point_de_vente_id)
);

CREATE INDEX idx_sondage_reponses_notification ON sondage_reponses(notification_id);

CREATE TABLE transactions (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  livraison_id UUID NOT NULL REFERENCES livraisons(id) ON DELETE CASCADE,
  montant      NUMERIC(12,2) NOT NULL,
  fournisseur  fournisseur_paiement NOT NULL,
  statut       statut_transaction NOT NULL DEFAULT 'en_attente',
  reference_cinetpay TEXT,
  date         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_transactions_livraison ON transactions(livraison_id);
CREATE INDEX idx_transactions_statut ON transactions(statut);
