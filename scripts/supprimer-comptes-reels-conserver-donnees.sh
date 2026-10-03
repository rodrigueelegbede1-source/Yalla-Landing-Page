#!/usr/bin/env bash
# Supprime les identités Auth des comptes réels, sans supprimer les données métier.
# Les comptes de démonstration connus sont exclus.
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

export PGPASSWORD="$DB_PASSWORD"
CONNEXION="postgresql://postgres.$REF@aws-1-eu-west-3.pooler.supabase.com:5432/postgres"
EXCLUS="'225070000010','225070000011','225070000012','225070000013','225070000014','225070000015'"

COMPTES="$(psql -w -tA -F '|' -v ON_ERROR_STOP=1 "$CONNEXION" -c "
  SELECT u.id, u.auth_user_id, u.telephone, u.role::text, u.nom
  FROM utilisateurs u
  WHERE u.auth_user_id IS NOT NULL
    AND u.telephone NOT IN ($EXCLUS)
  ORDER BY u.telephone;")"

if [ -z "$COMPTES" ]; then
  echo 'Aucun compte réel avec une identité Auth à supprimer.'
  exit 0
fi

echo 'Les identités de connexion suivantes seront supprimées :'
while IFS='|' read -r utilisateur_id auth_user_id telephone role nom; do
  printf '  %s | %s | %s | %s\n' "${telephone#225}" "$role" "$nom" "$auth_user_id"
done <<< "$COMPTES"
echo
echo 'Les données métier seront conservées, mais ces comptes ne pourront plus se connecter.'
printf 'Tapez SUPPRIMER pour confirmer : '
read -r confirmation
[ "$confirmation" = 'SUPPRIMER' ] || { echo 'Abandon.'; exit 0; }

# Détacher avant DELETE Auth : auth_user_id est une FK ON DELETE CASCADE.
# Cette étape empêche la suppression en cascade de la ligne utilisateur et de
# ses éventuelles lignes de rôle. Les données métier restent donc présentes.
psql -w -v ON_ERROR_STOP=1 "$CONNEXION" <<SQL
BEGIN;
UPDATE utilisateurs
SET auth_user_id = NULL
WHERE auth_user_id IS NOT NULL
  AND telephone NOT IN ($EXCLUS);
COMMIT;
SQL

echecs=0
while IFS='|' read -r utilisateur_id auth_user_id telephone role nom; do
  [ -n "$auth_user_id" ] || continue
  code="$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE \
    "$URL/auth/v1/admin/users/$auth_user_id" \
    -H "apikey: $SERVICE" \
    -H "Authorization: Bearer $SERVICE")"
  case "$code" in
    200|204) printf '  Supprimé : %s (%s)\n' "${telephone#225}" "$role" ;;
    *) printf '  ÉCHEC : %s (%s), HTTP %s\n' "${telephone#225}" "$role" "$code" >&2; echecs=$((echecs + 1));;
  esac
done <<< "$COMPTES"

if [ "$echecs" -ne 0 ]; then
  echo "$echecs identité(s) Auth non supprimée(s). Les données métier restent conservées."
  exit 1
fi

echo 'Identités de connexion supprimées. Données métier conservées.'
