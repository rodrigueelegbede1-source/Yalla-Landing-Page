#!/usr/bin/env bash
# Crée un administrateur Yalla sans toucher aux données métier existantes.
# Usage : bash scripts/creer-administrateur.sh [nom] [telephone]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FICHIER="${YALLA_ENV:-$HOME/Downloads/jarvis-starter-kit/.env}"
cd "$ROOT"

lire() {
  grep -E "^$1=" "$ENV_FICHIER" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'"' \r'
}
URL="$(lire SUPABASE_URL)"
SERVICE="$(lire SUPABASE_SERVICE_ROLE_KEY)"
DB_PASSWORD="$(lire SUPABASE_DB_PASSWORD)"
REF="$(printf '%s' "$URL" | sed 's|https://||; s|\.supabase\.co.*||')"
[ -n "$URL" ] && [ -n "$SERVICE" ] && [ -n "$DB_PASSWORD" ] || { echo 'Configuration Supabase incomplète'; exit 1; }
command -v curl >/dev/null 2>&1 || { echo 'curl introuvable'; exit 1; }
command -v psql >/dev/null 2>&1 || { echo 'psql introuvable'; exit 1; }

normaliser() {
  local v="${1//[^0-9]/}"
  if [ "${v:0:5}" = "00225" ]; then v="${v:2}"; fi
  if [ "${#v}" = "10" ]; then v="225$v"; fi
  [ "${#v}" = "13" ] || { echo "Numéro invalide : $1" >&2; exit 1; }
  printf '%s' "$v"
}

NOM="${1:-Administrateur Yalla}"
TEL="$(normaliser "${2:-0706303030}")"
EMAIL="${TEL}@yalla.ci"
CONNEXION="postgresql://postgres.$REF@aws-1-eu-west-3.pooler.supabase.com:5432/postgres"
export PGPASSWORD="$DB_PASSWORD"

if psql -w -tA -v ON_ERROR_STOP=1 "$CONNEXION" -c \
  "SELECT 1 FROM utilisateurs WHERE telephone = '$TEL' OR normaliser_telephone(telephone) = '$TEL' LIMIT 1;" | grep -q '^1$'; then
  echo "Un utilisateur existe déjà pour le numéro ${TEL#225}. Aucun doublon créé."
  exit 1
fi

MDP="${YALLA_ADMIN_PASSWORD:-}"
if [ -z "$MDP" ]; then
  MDP="$(LC_ALL=C tr -dc 'ABCDEFGHJKMNPQRSTUVWXYZ23456789' < <(head -c 256 /dev/urandom) | cut -c1-10)"
fi
[ "${#MDP}" -ge 8 ] || { echo 'Le mot de passe doit contenir au moins 8 caractères'; exit 1; }

reponse="$(curl -fsS -X POST "$URL/auth/v1/admin/users" \
  -H "apikey: $SERVICE" \
  -H "Authorization: Bearer $SERVICE" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$MDP\",\"email_confirm\":true}")"
auth_id="$(printf '%s' "$reponse" | sed -n 's/.*"id":"\([0-9a-f-]\{36\}\)".*/\1/p' | head -1)"
[ -n "$auth_id" ] || { echo 'Supabase Auth n’a pas renvoyé d’identifiant'; exit 1; }

if ! psql -w -v ON_ERROR_STOP=1 "$CONNEXION" \
  -v nom="$NOM" -v telephone="$TEL" -v auth_id="$auth_id" <<'SQL'
INSERT INTO utilisateurs (nom, telephone, role, auth_user_id)
VALUES (:'nom', :'telephone', 'administrateur', :'auth_id');
SQL
then
  curl -sS -o /dev/null -X DELETE "$URL/auth/v1/admin/users/$auth_id" \
    -H "apikey: $SERVICE" -H "Authorization: Bearer $SERVICE" || true
  echo 'La ligne métier n’a pas été créée; le compte Auth a été annulé.' >&2
  exit 1
fi

echo "Administrateur créé : $NOM"
echo "Identifiant : ${TEL#225}"
echo "Mot de passe : $MDP"
echo 'Conservez ce mot de passe : il ne sera plus affiché.'
