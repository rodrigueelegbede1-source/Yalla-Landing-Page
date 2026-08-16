#!/usr/bin/env bash
# Installe les dépendances de tous les sous-projets.
# Un outil absent (Flutter, psql) est signalé mais n'interrompt pas le script :
# un environnement partiellement provisionné doit rester utilisable.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

STATUS=0
say()  { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
warn() { printf '  \033[33m! %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓ %s\033[0m\n' "$1"; }

# ── Backend ────────────────────────────────────────────────────────────────
say "Backend (NestJS)"
if command -v npm >/dev/null 2>&1; then
  if [ -f backend/package-lock.json ]; then
    npm ci --prefix backend || npm install --prefix backend || STATUS=1
  else
    npm install --prefix backend || STATUS=1
  fi
  [ $STATUS -eq 0 ] && ok "dépendances backend installées"
else
  warn "npm introuvable — backend non installé"
  STATUS=1
fi

# ── Fichier d'environnement ────────────────────────────────────────────────
say "Configuration"
if [ ! -f backend/.env ] && [ -f backend/.env.example ]; then
  cp backend/.env.example backend/.env
  ok "backend/.env créé depuis .env.example — pensez à le renseigner"
else
  ok "backend/.env déjà présent (ou pas d'exemple à copier)"
fi

# ── Mobile ─────────────────────────────────────────────────────────────────
say "Mobile (Flutter)"
if command -v flutter >/dev/null 2>&1; then
  (cd mobile && flutter pub get) || warn "flutter pub get a échoué"
  ok "dépendances Flutter récupérées"
else
  warn "SDK Flutter absent — étape ignorée (sans impact sur backend/landing)"
fi

# ── Base de données ────────────────────────────────────────────────────────
say "Base de données"
if command -v psql >/dev/null 2>&1; then
  ok "psql disponible — appliquez les migrations avec : npm run db:migrate"
else
  warn "psql absent — l'API ne démarrera pas sans PostgreSQL + PostGIS"
fi

# ── Landing ────────────────────────────────────────────────────────────────
say "Landing page"
ok "aucune dépendance à installer (HTML/CSS/JS statique)"

printf '\n'
if [ $STATUS -eq 0 ]; then
  printf '\033[32mSetup terminé.\033[0m  npm run dev:backend  |  npm run dev:landing\n'
else
  printf '\033[33mSetup terminé avec des avertissements (voir ci-dessus).\033[0m\n'
fi
exit $STATUS
