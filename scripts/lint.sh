#!/usr/bin/env bash
# Vérifications statiques disponibles aujourd'hui.
# Aucun linter n'est configuré dans le projet : on se rabat sur le compilateur
# TypeScript et l'analyseur Dart, qui attrapent déjà l'essentiel.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

STATUS=0
say()  { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
warn() { printf '  \033[33m! %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓ %s\033[0m\n' "$1"; }

say "Backend — typage TypeScript"
if [ -d backend/node_modules ]; then
  npx --prefix backend tsc --noEmit -p backend/tsconfig.json && ok "typage correct" || STATUS=1
else
  warn "backend/node_modules absent — lancez d'abord : npm run setup"
fi

say "Mobile — analyse Dart"
if command -v flutter >/dev/null 2>&1; then
  (cd mobile && flutter analyze) || STATUS=1
else
  warn "SDK Flutter absent — étape ignorée"
fi

say "Schéma — alignement entités / migrations SQL"
if command -v node >/dev/null 2>&1; then
  node scripts/audit-schema.js || STATUS=1
else
  warn "node absent — étape ignorée"
fi

say "Landing — syntaxe JavaScript"
if command -v node >/dev/null 2>&1; then
  node --check landing/script.js && ok "landing/script.js valide" || STATUS=1
  node --check landing/server.js && ok "landing/server.js valide" || STATUS=1
else
  warn "node absent — étape ignorée"
fi

printf '\n'
[ $STATUS -eq 0 ] && printf '\033[32mLint OK.\033[0m\n' || printf '\033[31mLint : erreurs détectées.\033[0m\n'
exit $STATUS
