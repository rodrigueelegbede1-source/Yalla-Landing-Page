#!/usr/bin/env bash
# Applique toutes les migrations Supabase sur un PostgreSQL ordinaire et signale
# la première qui échoue.
#
#   bash supabase/tests/verifier-migrations.sh
#
# Variables : PGHOST PGPORT PGUSER PGPASSWORD (standard psql), PGDATABASE_TEST
# (défaut : yalla_sb). La base de test est recréée à chaque exécution.
#
# À quoi ça sert : `supabase db push` qui échoue à mi-parcours laisse la base
# distante dans un état intermédiaire, avec une partie des migrations appliquées
# et pas les autres. Autant échouer ici, sur une base jetable.
#
# CE QUI N'EST PAS VÉRIFIÉ ICI, et qu'il ne faut pas croire vérifié :
#   * le comportement réel des politiques RLS sous une identité Supabase
#   * le hook d'émission de jeton, appelé par le service d'authentification
#   * la diffusion Realtime
#   * l'exécution effective des tâches pg_cron
# L'extension pg_cron n'existant pas sur un PostgreSQL ordinaire, sa ligne de
# création est neutralisée le temps du test. Le reste du fichier, lui, est bien
# exécuté. Ces quatre points exigent un vrai projet Supabase.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

DB="${PGDATABASE_TEST:-yalla_sb}"
PSQL="psql -v ON_ERROR_STOP=1 -q"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
ok()  { printf '  \033[32m✓ %s\033[0m\n' "$1"; }
die() { printf '  \033[31m✗ %s\033[0m\n' "$1"; exit 1; }

command -v psql >/dev/null 2>&1 || die "psql introuvable dans le PATH"

say "Base de test $DB"
$PSQL -d postgres -c "DROP DATABASE IF EXISTS $DB" >/dev/null 2>&1
$PSQL -d postgres -c "CREATE DATABASE $DB" >/dev/null 2>&1 || die "création de la base impossible"
$PSQL -d "$DB" -c "CREATE EXTENSION IF NOT EXISTS postgis" >/dev/null 2>&1 \
  || die "PostGIS indisponible : installez-le, il est indispensable au schéma"
$PSQL -d "$DB" -c "CREATE EXTENSION IF NOT EXISTS pgcrypto" >/dev/null 2>&1
ok "base recréée avec PostGIS"

say "Simulation de l'environnement Supabase"
$PSQL -d "$DB" -f supabase/tests/stubs_supabase_local.sql >/dev/null 2>&1 \
  || die "les simulacres Supabase n'ont pas pu être posés"
ok "schéma auth, rôles, publication et pg_cron simulés"

say "Migrations"
ECHEC=0
for f in supabase/migrations/*.sql; do
  nom="$(basename "$f" .sql)"
  cible="$f"

  # pg_cron n'existe pas sur un PostgreSQL ordinaire. On neutralise les deux
  # instructions qui s'adressent à l'extension elle-même, sa création et son
  # commentaire, pour pouvoir exécuter le reste du fichier : les tâches
  # planifiées et la publication Realtime, qui sont la partie intéressante.
  # On ne neutralise que la création de l'extension elle-même, pas les fichiers
  # qui se contentent de mentionner pg_cron dans un commentaire.
  if grep -q '^CREATE EXTENSION IF NOT EXISTS pg_cron;' "$f"; then
    cible="$TMP/$nom.sql"
    sed 's/^CREATE EXTENSION IF NOT EXISTS pg_cron;/-- neutralisé pour le test local/' "$f" > "$cible"
    nom="$nom (hors extension pg_cron)"
  fi

  printf '  %-56s' "${nom:15}"
  if $PSQL -d "$DB" -f "$cible" >"$TMP/sortie" 2>&1; then
    printf '\033[32mOK\033[0m\n'
  else
    printf '\033[31mECHEC\033[0m\n'
    # On extrait la vraie erreur : le reste de la sortie n'est que le résultat
    # des requêtes qui ont réussi avant, et il noie le message utile.
    grep -E "ERROR|FATAL|ERREUR|DETAIL|D.TAIL" "$TMP/sortie" | head -6 | sed 's/^/      /'
    ECHEC=1
    break
  fi
done

[ "$ECHEC" = "0" ] || die "migration en échec, rien n'a été poussé"

say "Contrôles de cohérence"
NB_T=$($PSQL -tA -d "$DB" -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'")
NB_V=$($PSQL -tA -d "$DB" -c "SELECT count(*) FROM information_schema.views WHERE table_schema='public'")
NB_P=$($PSQL -tA -d "$DB" -c "SELECT count(*) FROM pg_policies WHERE schemaname='public'")
NB_R=$($PSQL -tA -d "$DB" -c "SELECT count(*) FROM pg_tables WHERE schemaname='public' AND rowsecurity")
NB_C=$($PSQL -tA -d "$DB" -c "SELECT count(*) FROM cron.job")
printf '  tables               : %s\n' "$NB_T"
printf '  vues                 : %s\n' "$NB_V"
printf '  politiques RLS       : %s\n' "$NB_P"
printf '  tables sous RLS      : %s\n' "$NB_R"
printf '  tâches planifiées    : %s\n' "$NB_C"

# Une table sans RLS est une table où tout le monde peut tout lire.
# On écarte les tables appartenant à une extension : `spatial_ref_sys` est le
# référentiel de systèmes de coordonnées de PostGIS, il est public par nature et
# ne nous appartient pas.
NON_PROTEGEES=$($PSQL -tA -d "$DB" -c "
  SELECT string_agg(t.tablename, ', ')
    FROM pg_tables t
    JOIN pg_class c ON c.relname = t.tablename
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = t.schemaname
   WHERE t.schemaname='public' AND NOT t.rowsecurity
     AND NOT EXISTS (SELECT 1 FROM pg_depend d
                      WHERE d.objid = c.oid AND d.deptype = 'e')")
if [ -n "$NON_PROTEGEES" ]; then
  printf '  \033[31m✗ tables SANS RLS : %s\033[0m\n' "$NON_PROTEGEES"
  die "toute table du schéma public doit être sous RLS"
fi
ok "toutes les tables sont sous RLS"

# Une vue sans security_invoker contourne silencieusement toutes les politiques.
VUES_FUITE=$($PSQL -tA -d "$DB" -c "
  SELECT string_agg(c.relname, ', ')
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname='public' AND c.relkind='v'
     AND NOT EXISTS (SELECT 1 FROM pg_depend d
                      WHERE d.objid = c.oid AND d.deptype = 'e')
     AND lower(COALESCE((SELECT option_value FROM pg_options_to_table(c.reloptions)
                          WHERE option_name='security_invoker'), 'off'))
         NOT IN ('on','true','yes','1')")
if [ -n "$VUES_FUITE" ]; then
  printf '  \033[31m✗ vues qui contournent RLS : %s\033[0m\n' "$VUES_FUITE"
  die "toute vue doit être en security_invoker"
fi
ok "toutes les vues respectent RLS"

say "Données de départ"
if $PSQL -d "$DB" -f supabase/seed.sql >"$TMP/seed" 2>&1; then
  ok "seed appliqué"
else
  grep -E "ERROR|ERREUR|DETAIL|D.TAIL" "$TMP/seed" | head -6 | sed 's/^/      /'
  die "le seed échoue"
fi

say "Suites de tests"
for suite in supabase/tests/test_*.sql; do
  nom="$(basename "$suite" .sql)"
  if $PSQL -d "$DB" -f "$suite" >"$TMP/suite" 2>&1; then
    n=$(grep -c "ok " "$TMP/suite")
    ok "$nom : $n cas passés"
  else
    printf '  \033[31m✗ %s\033[0m\n' "$nom"
    grep -E "ERROR|ERREUR|assertion|ok " "$TMP/suite" | head -14 | sed 's/^/      /'
    die "suite en échec"
  fi
done

printf '\n\033[32mMigrations Supabase validées.\033[0m\n\n'
