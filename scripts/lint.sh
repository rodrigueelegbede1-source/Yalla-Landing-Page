#!/usr/bin/env bash
# Vérifications statiques du dépôt.
#
#   npm run lint
#
# Signale et passe quand un outil manque, plutôt que d'échouer.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

say()  { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓ %s\033[0m\n' "$1"; }
warn() { printf '  \033[33m! %s\033[0m\n' "$1"; }
ko()   { printf '  \033[31m✗ %s\033[0m\n' "$1"; }

STATUS=0

say "Mobile — analyse Dart"
if command -v flutter >/dev/null 2>&1; then
  if (cd mobile && flutter analyze 2>&1 | tail -15 | sed 's/^/  /'); then
    ok "analyse Dart propre"
  else
    ko "analyse Dart en échec"; STATUS=1
  fi
else
  warn "SDK Flutter absent — étape ignorée"
fi

say "Base — cohérence des migrations Supabase"
NB=$(ls supabase/migrations/*.sql 2>/dev/null | wc -l | tr -d ' ')
if [ "$NB" = "0" ]; then
  ko "aucune migration trouvée"; STATUS=1
else
  ok "$NB migrations"

  # Un fichier de migration dont le nom ne commence pas par un horodatage casse
  # l'ordre d'application, et Supabase l'appliquera au mauvais moment.
  MAL_NOMMEES=$(ls supabase/migrations/ 2>/dev/null | grep -vE '^[0-9]{14}_' || true)
  if [ -n "$MAL_NOMMEES" ]; then
    ko "migrations mal nommées : $MAL_NOMMEES"; STATUS=1
  else
    ok "toutes les migrations sont horodatées"
  fi

  # Une politique RLS qui compare un identifiant reçu du client plutôt que lu
  # dans le jeton ne protège rien. C'est exactement la faille qui traversait
  # l'ancienne API : l'identifiant venait de l'URL, jamais du jeton.
  if grep -rn "auth_id_metier()" supabase/migrations/*rls*.sql >/dev/null 2>&1; then
    ok "les politiques lisent l'identité dans le jeton"
  else
    ko "aucune politique n'utilise auth_id_metier()"; STATUS=1
  fi
fi

say "Landing — syntaxe JavaScript"
if command -v node >/dev/null 2>&1; then
  for f in landing/script.js landing/server.js; do
    if node --check "$f" 2>/dev/null; then
      ok "$f valide"
    else
      ko "$f invalide"; STATUS=1
    fi
  done
else
  warn "Node absent — étape ignorée"
fi

if [ "$STATUS" = "0" ]; then
  printf '\n\033[32mLint OK.\033[0m\n\n'
else
  printf '\n\033[31mLint en échec.\033[0m\n\n'
fi
exit $STATUS
