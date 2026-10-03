#!/usr/bin/env bash
# Crée un réseau Yalla complet pour démonstration.
#
#   bash scripts/amorcer-demonstration.sh
#
# Les mots de passe sont générés à l'exécution et affichés une seule fois.
# Les comptes utilisent des numéros de démonstration dédiés, configurables par
# DEMO_TEL_ADMIN, DEMO_TEL_AGENT, DEMO_TEL_FABRICANT, DEMO_TEL_DISTRIBUTEUR,
# DEMO_TEL_BOUTIQUE et DEMO_TEL_LIVREUR.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FICHIER="${YALLA_ENV:-$HOME/Downloads/jarvis-starter-kit/.env}"
cd "$ROOT"

lire() {
  grep -E "^$1=" "$ENV_FICHIER" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'"' \r'
}

URL="$(lire SUPABASE_URL)"
CLE_SERVICE="$(lire SUPABASE_SERVICE_ROLE_KEY)"
MDP_BASE="$(lire SUPABASE_DB_PASSWORD)"
REF="$(printf '%s' "$URL" | sed 's|https://||; s|\.supabase\.co.*||')"

[ -n "$URL" ] || { echo "SUPABASE_URL absente de $ENV_FICHIER"; exit 1; }
[ -n "$CLE_SERVICE" ] || { echo "SUPABASE_SERVICE_ROLE_KEY absente de $ENV_FICHIER"; exit 1; }
[ -n "$MDP_BASE" ] || { echo "SUPABASE_DB_PASSWORD absente de $ENV_FICHIER"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl introuvable"; exit 1; }
command -v psql >/dev/null 2>&1 || { echo "psql introuvable"; exit 1; }

CONNEXION="postgresql://postgres.$REF@aws-1-eu-west-3.pooler.supabase.com:5432/postgres"
export PGPASSWORD="$MDP_BASE"

normaliser() {
  local v="${1//[^0-9]/}"
  if [ "${v:0:5}" = "00225" ]; then v="${v:2}"; fi
  if [ "${#v}" = "10" ]; then v="225$v"; fi
  [ "${#v}" = "13" ] || { echo "Numéro invalide : $1" >&2; return 1; }
  printf '%s' "$v"
}

motdepasse() {
  LC_ALL=C tr -dc 'ABCDEFGHJKMNPQRSTUVWXYZ23456789' < <(head -c 256 /dev/urandom) | cut -c1-8
}

echappe_json() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

creer_auth() {
  local nom="$1" tel="$2" mdp="$3" email reponse auth_id
  email="${tel}@yalla.ci"
  reponse="$(curl -fsS -X POST "$URL/auth/v1/admin/users" \
    -H "apikey: $CLE_SERVICE" \
    -H "Authorization: Bearer $CLE_SERVICE" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$mdp\",\"email_confirm\":true}")" || {
      echo "Création Auth impossible pour $nom. Le numéro existe peut-être déjà." >&2
      exit 1
    }
  auth_id="$(printf '%s' "$reponse" | sed -n 's/.*"id":"\([0-9a-f-]\{36\}\)".*/\1/p' | head -1)"
  [ -n "$auth_id" ] || { echo "Réponse Auth invalide pour $nom" >&2; exit 1; }
  printf '%s' "$auth_id"
}

ADMIN_TEL="$(normaliser "${DEMO_TEL_ADMIN:-0700000010}")"
AGENT_TEL="$(normaliser "${DEMO_TEL_AGENT:-0700000011}")"
FAB_TEL="$(normaliser "${DEMO_TEL_FABRICANT:-0700000012}")"
DIST_TEL="$(normaliser "${DEMO_TEL_DISTRIBUTEUR:-0700000013}")"
BOUT_TEL="$(normaliser "${DEMO_TEL_BOUTIQUE:-0700000014}")"
LIV_TEL="$(normaliser "${DEMO_TEL_LIVREUR:-0700000015}")"

MDP_ADMIN="$(motdepasse)"
MDP_AGENT="$(motdepasse)"
MDP_FAB="$(motdepasse)"
MDP_DIST="$(motdepasse)"
MDP_BOUT="$(motdepasse)"
MDP_LIV="$(motdepasse)"

echo "Création des comptes Auth de démonstration..."
ADMIN_AUTH="$(creer_auth 'Administrateur Demo' "$ADMIN_TEL" "$MDP_ADMIN")"
AGENT_AUTH="$(creer_auth 'Agent Demo' "$AGENT_TEL" "$MDP_AGENT")"
FAB_AUTH="$(creer_auth 'Fabricant Demo' "$FAB_TEL" "$MDP_FAB")"
DIST_AUTH="$(creer_auth 'Distributeur Demo' "$DIST_TEL" "$MDP_DIST")"
BOUT_AUTH="$(creer_auth 'Boutique Demo' "$BOUT_TEL" "$MDP_BOUT")"
LIV_AUTH="$(creer_auth 'Livreur Demo' "$LIV_TEL" "$MDP_LIV")"

psql -w -v ON_ERROR_STOP=1 "$CONNEXION" \
  -v admin_auth="$ADMIN_AUTH" -v agent_auth="$AGENT_AUTH" \
  -v fab_auth="$FAB_AUTH" -v dist_auth="$DIST_AUTH" \
  -v bout_auth="$BOUT_AUTH" -v liv_auth="$LIV_AUTH" \
  -v admin_tel="$ADMIN_TEL" -v agent_tel="$AGENT_TEL" \
  -v fab_tel="$FAB_TEL" -v dist_tel="$DIST_TEL" \
  -v bout_tel="$BOUT_TEL" -v liv_tel="$LIV_TEL" <<'SQL'
BEGIN;

INSERT INTO utilisateurs (nom, telephone, role, auth_user_id)
VALUES ('Administrateur Demo', :'admin_tel', 'administrateur', :'admin_auth');

INSERT INTO utilisateurs (nom, telephone, role, auth_user_id)
VALUES ('Agent Demo', :'agent_tel', 'agent_recenseur', :'agent_auth')
RETURNING id AS agent_user_id \gset
INSERT INTO agents_recenseurs (utilisateur_id, secteur)
VALUES (:'agent_user_id', 'Cocody - démonstration')
RETURNING id AS agent_id \gset

INSERT INTO utilisateurs (nom, telephone, role, auth_user_id)
VALUES ('Fabricant Demo', :'fab_tel', 'fabricant', :'fab_auth')
RETURNING id AS fab_user_id \gset
INSERT INTO fabricants (utilisateur_id, nom)
VALUES (:'fab_user_id', 'Ivoire Demo')
RETURNING id AS fab_id \gset

INSERT INTO utilisateurs (nom, telephone, role, auth_user_id)
VALUES ('Distributeur Demo', :'dist_tel', 'distributeur', :'dist_auth')
RETURNING id AS dist_user_id \gset
INSERT INTO distributeurs (utilisateur_id, fabricant_id, nom, telephone)
VALUES (:'dist_user_id', :'fab_id', 'Distribution Demo', :'dist_tel')
RETURNING id AS dist_id \gset

INSERT INTO utilisateurs (nom, telephone, role, auth_user_id)
VALUES ('Boutique Demo', :'bout_tel', 'point_de_vente', :'bout_auth')
RETURNING id AS bout_user_id \gset
INSERT INTO points_de_vente (
  nom, type_activite, commune, ville, adresse, position, gerant_nom,
  telephone, statut, agent_recenseur_id, utilisateur_id
)
VALUES (
  'Boutique Demo', 'boutique', 'Cocody', 'Abidjan', 'Riviera 2',
  ST_SetSRID(ST_MakePoint(-3.9667, 5.3599), 4326)::GEOGRAPHY,
  'Boutique Demo', :'bout_tel', 'actif', :'agent_id', :'bout_user_id'
)
RETURNING id AS bout_id \gset

INSERT INTO utilisateurs (nom, telephone, role, auth_user_id)
VALUES ('Livreur Demo', :'liv_tel', 'livreur', :'liv_auth')
RETURNING id AS liv_user_id \gset
INSERT INTO livreurs (utilisateur_id, distributeur_id)
VALUES (:'liv_user_id', :'dist_id');

INSERT INTO categories_produit (nom)
VALUES ('Boissons')
ON CONFLICT (nom) DO NOTHING;
INSERT INTO produits (fabricant_id, nom, reference, categorie_id)
SELECT :'fab_id', 'Eau Demo 1,5L', 'DEMO-EAU15', id
FROM categories_produit WHERE nom = 'Boissons'
ON CONFLICT (fabricant_id, reference) DO NOTHING
RETURNING id AS produit_id \gset

INSERT INTO attributions_reseau (fabricant_id, point_de_vente_id, distributeur_id)
VALUES (:'fab_id', :'bout_id', :'dist_id')
ON CONFLICT (fabricant_id, point_de_vente_id)
DO UPDATE SET distributeur_id = EXCLUDED.distributeur_id;

INSERT INTO stocks (point_de_vente_id, produit_id, quantite)
VALUES (:'bout_id', :'produit_id', 10)
ON CONFLICT (point_de_vente_id, produit_id) WHERE produit_id IS NOT NULL
DO UPDATE SET quantite = EXCLUDED.quantite, date_maj = now();

COMMIT;
SQL

echo
echo 'Comptes de démonstration créés. Notez ces accès maintenant :'
printf '%-22s %s / %s\n' 'Administrateur web' "$ADMIN_TEL" "$MDP_ADMIN"
printf '%-22s %s / %s\n' 'Agent recenseur mobile' "$AGENT_TEL" "$MDP_AGENT"
printf '%-22s %s / %s\n' 'Fabricant web' "$FAB_TEL" "$MDP_FAB"
printf '%-22s %s / %s\n' 'Distributeur web/mobile' "$DIST_TEL" "$MDP_DIST"
printf '%-22s %s / %s\n' 'Point de vente mobile' "$BOUT_TEL" "$MDP_BOUT"
printf '%-22s %s / %s\n' 'Livreur mobile' "$LIV_TEL" "$MDP_LIV"
echo
echo 'Accès web : https://yalla.ci/rejoindre.html'
echo 'Ne distribuez pas ces comptes : ils sont réservés à la démonstration.'
