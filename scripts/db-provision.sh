#!/usr/bin/env bash
# Crée la base Yalla, applique les 10 migrations et le seed de développement.
# Suppose psql accessible et un serveur PostgreSQL démarré avec PostGIS disponible.
#
#   PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGPASSWORD=... bash scripts/db-provision.sh
#
# Variables reconnues : PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE (défaut: yalla)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DB="${PGDATABASE:-yalla}"
export PGHOST="${PGHOST:-127.0.0.1}" PGPORT="${PGPORT:-5432}" PGUSER="${PGUSER:-postgres}"
PSQL="psql -v ON_ERROR_STOP=1 -q"

say() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
ok()  { printf '  \033[32m✓ %s\033[0m\n' "$1"; }
die() { printf '  \033[31m✗ %s\033[0m\n' "$1"; exit 1; }

command -v psql >/dev/null 2>&1 || die "psql introuvable dans le PATH"

say "Connexion"
$PSQL -d postgres -c "select 1" >/dev/null 2>&1 || die "serveur injoignable sur $PGHOST:$PGPORT"
ok "serveur joignable ($PGHOST:$PGPORT)"

say "Base $DB + PostGIS"
if [ "${DB_RESET:-0}" = "1" ]; then
  $PSQL -d postgres -c "DROP DATABASE IF EXISTS $DB" >/dev/null && ok "ancienne base supprimée (DB_RESET=1)"
fi
$PSQL -d postgres -c "CREATE DATABASE $DB" >/dev/null 2>&1 && ok "base créée" || ok "base déjà existante"
# PostGIS est indispensable : colonnes geography et index spatiaux.
$PSQL -d "$DB" -c "CREATE EXTENSION IF NOT EXISTS postgis" >/dev/null \
  || die "extension postgis indisponible — installez le paquet postgis pour cette version de PostgreSQL"
ok "PostGIS $($PSQL -tA -d "$DB" -c 'select postgis_version()' 2>/dev/null | head -1)"

say "Migrations"
for f in database/migrations/*.sql; do
  printf '  %-48s' "$(basename "$f")"
  if $PSQL -d "$DB" -f "$f" >/dev/null 2>/tmp/yalla_mig.err; then
    printf '\033[32mOK\033[0m\n'
  else
    printf '\033[31mECHEC\033[0m\n'; sed 's/^/      /' /tmp/yalla_mig.err; exit 1
  fi
done

say "Seed de développement"
if $PSQL -d "$DB" -f database/seed/seed_dev.sql >/dev/null 2>/tmp/yalla_seed.err; then
  ok "seed appliqué"
else
  sed 's/^/  /' /tmp/yalla_seed.err; die "seed en échec"
fi

say "Résultat"
$PSQL -tA -d "$DB" -c "select 'tables : ' || count(*) from information_schema.tables where table_schema='public'"
printf '\n\033[32mBase prête.\033[0m Renseignez backend/.env puis lancez : npm run dev:backend\n'
