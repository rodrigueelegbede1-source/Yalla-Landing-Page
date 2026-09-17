#!/usr/bin/env bash
# Pousse les migrations sur Supabase, puis force PostgREST à relire le schéma.
#
#   npm run db:deploy
#
# POURQUOI LE RECHARGEMENT N'EST PAS OPTIONNEL. PostgREST tient un cache du
# schéma et ne le relit pas de lui-même après un `db push`. Une fonction
# fraîchement déployée existe alors en base, répond parfaitement sous `psql`, et
# l'API ferme la connexion sans rien dire : `curl: (52) Empty reply from server`,
# sans code HTTP et sans journal. C'est le plus déroutant des pièges rencontrés,
# parce que rien n'indique que le problème est un cache.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ENV_FICHIER="${YALLA_ENV:-$HOME/Downloads/jarvis-starter-kit/.env}"
lire() {
  grep -E "^$1=" "$ENV_FICHIER" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'"' \r'
}

export SUPABASE_ACCESS_TOKEN="${SUPABASE_ACCESS_TOKEN:-$(lire SUPABASE_ACCESS_TOKEN)}"
export SUPABASE_DB_PASSWORD="${SUPABASE_DB_PASSWORD:-$(lire SUPABASE_DB_PASSWORD)}"
URL="$(lire SUPABASE_URL)"
REF="$(printf '%s' "$URL" | sed 's|https://||; s|\.supabase\.co.*||')"

[ -n "$SUPABASE_ACCESS_TOKEN" ] || { echo "SUPABASE_ACCESS_TOKEN absente de $ENV_FICHIER"; exit 1; }
[ -n "$SUPABASE_DB_PASSWORD" ]  || { echo "SUPABASE_DB_PASSWORD absente de $ENV_FICHIER"; exit 1; }
[ -n "$REF" ]                   || { echo "SUPABASE_URL absente ou mal formée"; exit 1; }

echo
echo "▸ Migrations"
npx --yes supabase@latest db push --include-all

echo
echo "▸ Rechargement du cache de schéma PostgREST"
PGPASSWORD="$SUPABASE_DB_PASSWORD" \
  psql "postgresql://postgres.$REF@aws-1-eu-west-3.pooler.supabase.com:5432/postgres" \
       -w -q -c "NOTIFY pgrst, 'reload schema'"

# Le rechargement est asynchrone : PostgREST reçoit la notification et relit le
# schéma. Quelques secondes suffisent, mais appeler l'API trop tôt donne encore
# l'ancien cache, donc un échec qui semble démentir le déploiement.
sleep 5
echo "  cache rechargé"

echo
echo "Base à jour. Si une fonction reste introuvable, relancez ce script :"
echo "le rechargement est asynchrone et peut manquer une instance."
echo
