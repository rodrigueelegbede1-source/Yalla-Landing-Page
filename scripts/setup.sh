#!/usr/bin/env bash
# Vérifie l'outillage et installe les dépendances.
#
#   npm run setup
#
# Comme les autres scripts du dépôt, celui-ci signale et passe quand un outil
# manque, plutôt que d'échouer : un environnement partiellement provisionné doit
# rester utilisable.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

say()  { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓ %s\033[0m\n' "$1"; }
warn() { printf '  \033[33m! %s\033[0m\n' "$1"; }

MANQUE=0

say "Outillage"

if command -v supabase >/dev/null 2>&1; then
  ok "CLI Supabase $(supabase --version 2>/dev/null | head -1)"
else
  warn "CLI Supabase absent — installez-le : npm install -g supabase"
  MANQUE=1
fi

if command -v flutter >/dev/null 2>&1; then
  ok "Flutter $(flutter --version 2>/dev/null | head -1 | cut -d' ' -f2)"
else
  warn "Flutter absent du PATH — https://docs.flutter.dev/get-started/install/windows"
  MANQUE=1
fi

if command -v psql >/dev/null 2>&1; then
  ok "psql $(psql --version 2>/dev/null | awk '{print $3}')"
else
  warn "psql absent — nécessaire seulement pour 'npm run db:verifier' en local"
fi

if command -v node >/dev/null 2>&1; then
  ok "Node $(node --version)"
else
  warn "Node absent"
  MANQUE=1
fi

say "Application mobile"
if command -v flutter >/dev/null 2>&1; then
  if [ -d mobile/android ]; then
    ok "plateforme Android présente"
  else
    warn "mobile/android absent — lancez : cd mobile && flutter create ."
  fi
  (cd mobile && flutter pub get 2>&1 | tail -3 | sed 's/^/  /') \
    && ok "dépendances Flutter résolues" \
    || warn "flutter pub get en échec"
else
  warn "étape ignorée, Flutter absent"
fi

say "Base de données"
if [ -f supabase/config.toml ]; then
  ok "projet Supabase initialisé ($(ls supabase/migrations/*.sql 2>/dev/null | wc -l | tr -d ' ') migrations)"
  printf '    Pour relier un projet distant : supabase link --project-ref <ref>\n'
  printf '    Puis appliquer le schéma      : npm run db:push\n'
else
  warn "supabase/config.toml absent — lancez : supabase init"
fi

if [ "$MANQUE" = "0" ]; then
  printf '\n\033[32mEnvironnement prêt.\033[0m\n\n'
else
  printf '\n\033[33mEnvironnement incomplet, voir les avertissements ci-dessus.\033[0m\n\n'
fi
