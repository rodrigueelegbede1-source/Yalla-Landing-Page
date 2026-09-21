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

# Vérifié AVANT de pousser quoi que ce soit. Sans cette garde, les migrations
# partaient puis le rechargement du cache échouait en « psql: command not
# found », laissant PostgREST sur un schéma périmé : les nouvelles fonctions
# répondaient `Empty reply from server`, sans que rien ne relie ce symptôme au
# déploiement qui venait de réussir.
if ! command -v psql >/dev/null 2>&1; then
  echo
  echo "  psql est introuvable dans le PATH."
  echo "  Il est nécessaire pour recharger le cache de schéma de PostgREST après"
  echo "  la migration, sans quoi les fonctions déployées restent invisibles de"
  echo "  l'API. Ajoutez le dossier bin de PostgreSQL au PATH, puis relancez."
  exit 1
fi

echo
echo "▸ Migrations"
npx --yes supabase@latest db push --include-all

echo
echo "▸ Rechargement du cache de schéma PostgREST"

# LES OPTIONS PASSENT AVANT LA CHAÎNE DE CONNEXION, et ce n'est pas une
# coquetterie de style. Le `getopt` livré avec PostgreSQL sous Windows ne
# réordonne pas les arguments : il s'arrête au premier qui n'est pas une
# option. Avec l'URL en tête, `-w -q -c "NOTIFY…"` était lu comme un nom
# d'utilisateur suivi de trois arguments de trop, et psql se contentait
# d'écrire « option supplémentaire ignorée » avant de sortir avec le code 0.
#
# Autrement dit la notification n'était jamais envoyée, le script annonçait
# « cache rechargé » sans avoir rien rechargé, et `set -e` ne voyait rien
# passer. Le déploiement fonctionnait quand même, parce que PostgREST recharge
# aussi de lui-même sur événement DDL, mais la garde ne gardait rien.
REPONSE="$(
  PGPASSWORD="$SUPABASE_DB_PASSWORD" \
  psql -w -q -At \
       -c "NOTIFY pgrst, 'reload schema'; SELECT 'notifie';" \
       "postgresql://postgres.$REF@aws-1-eu-west-3.pooler.supabase.com:5432/postgres"
)"

# On vérifie ce que la base a répondu, pas ce que psql a rendu comme code de
# sortie : c'est précisément la différence qui avait masqué le défaut.
if [ "$REPONSE" != "notifie" ]; then
  echo "  la notification n'est pas partie (réponse : « $REPONSE »)"
  echo "  les fonctions déployées peuvent rester invisibles de l'API."
  exit 1
fi

# Le rechargement est asynchrone : PostgREST reçoit la notification et relit le
# schéma. Quelques secondes suffisent, mais appeler l'API trop tôt donne encore
# l'ancien cache, donc un échec qui semble démentir le déploiement.
sleep 5
echo "  cache rechargé"

echo
echo "Base à jour. Si une fonction reste introuvable, relancez ce script :"
echo "le rechargement est asynchrone et peut manquer une instance."
echo
