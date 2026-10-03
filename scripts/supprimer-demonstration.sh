#!/usr/bin/env bash
# Supprime uniquement le réseau de démonstration Yalla.
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

# Les numéros sont la clé de ciblage, jamais un filtre approximatif sur le nom.
NUMEROS="225070000010 225070000011 225070000012 225070000013 225070000014 225070000015"

IDS="$(psql -w -tA -F '|' -v ON_ERROR_STOP=1 "$CONNEXION" -c "
  SELECT id, auth_user_id, telephone
  FROM utilisateurs
  WHERE telephone IN ('225070000010','225070000011','225070000012','225070000013','225070000014','225070000015')
  ORDER BY telephone;")"

if [ -z "$IDS" ]; then
  echo 'Aucun compte de démonstration trouvé.'
  exit 0
fi

echo 'Comptes ciblés :'
printf '%s\n' "$IDS" | cut -d'|' -f3

# Supprime d'abord les identités Auth. La FK auth_user_id en cascade supprime
# l'utilisateur métier. Les tables dont le lien est SET NULL sont nettoyées
# explicitement dans la transaction SQL ci-dessous.
while IFS='|' read -r utilisateur_id auth_user_id telephone; do
  [ -n "$auth_user_id" ] || continue
  code="$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE \
    "$URL/auth/v1/admin/users/$auth_user_id" \
    -H "apikey: $SERVICE" \
    -H "Authorization: Bearer $SERVICE")"
  case "$code" in
    200|204) echo "Auth supprimé : ${telephone#225}" ;;
    *) echo "Échec Auth ${telephone#225} : HTTP $code" >&2; exit 1;;
  esac
done <<< "$IDS"

psql -w -v ON_ERROR_STOP=1 "$CONNEXION" <<'SQL'
BEGIN;

-- Nettoyage strict par téléphone / nom de démonstration uniquement.
DELETE FROM attributions_reseau
WHERE point_de_vente_id IN (
  SELECT id FROM points_de_vente WHERE telephone IN ('2250700000014') OR nom = 'Boutique Demo'
) OR fabricant_id IN (
  SELECT id FROM fabricants WHERE nom = 'Ivoire Demo'
);

DELETE FROM stocks
WHERE point_de_vente_id IN (SELECT id FROM points_de_vente WHERE telephone IN ('2250700000014') OR nom = 'Boutique Demo')
   OR produit_id IN (SELECT id FROM produits WHERE fabricant_id IN (SELECT id FROM fabricants WHERE nom = 'Ivoire Demo'));

DELETE FROM produits WHERE fabricant_id IN (SELECT id FROM fabricants WHERE nom = 'Ivoire Demo');
DELETE FROM positions_livreurs WHERE livreur_id IN (SELECT id FROM livreurs WHERE utilisateur_id IN (SELECT id FROM utilisateurs WHERE telephone IN ('2250700000015')));
DELETE FROM livreurs WHERE utilisateur_id IN (SELECT id FROM utilisateurs WHERE telephone IN ('2250700000015'));
DELETE FROM distributeurs WHERE utilisateur_id IN (SELECT id FROM utilisateurs WHERE telephone IN ('2250700000013')) OR nom = 'Distribution Demo';
DELETE FROM points_de_vente WHERE telephone IN ('2250700000014') OR nom = 'Boutique Demo';
DELETE FROM fabricants WHERE nom = 'Ivoire Demo';
DELETE FROM agents_recenseurs WHERE secteur = 'Cocody - démonstration';

-- Auth cascade normalement ces lignes. Cette suppression rend le script
-- idempotent même si un compte Auth était déjà absent.
DELETE FROM utilisateurs
WHERE telephone IN ('2250700000010','2250700000011','2250700000012','2250700000013','2250700000014','2250700000015');

COMMIT;
SQL

echo 'Comptes et données de démonstration supprimés.'
