#!/usr/bin/env bash
# Suites de tests du dépôt.
#
#   npm run test
#
# La suite SQL est la seule qui existe aujourd'hui, et elle couvre le mécanisme
# central du produit : routage automatique d'une rupture née d'une vente, deux
# cercles d'accès, non-réescalade, concurrence entre deux preneurs, péremption.
#
# Elle tourne sur un PostgreSQL ordinaire grâce aux simulacres de
# supabase/tests/, sans projet Supabase ni Docker. Ce qu'elle ne couvre pas :
# le comportement réel des politiques RLS sous une identité Supabase, le hook
# d'émission de jeton, Realtime et l'exécution de pg_cron.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

say()  { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
warn() { printf '  \033[33m! %s\033[0m\n' "$1"; }

STATUS=0

MOBILE_TESTS=$(find mobile/test -name '*_test.dart' 2>/dev/null | wc -l | tr -d ' ')
SQL_TESTS=$(find supabase/tests -name 'test_*.sql' 2>/dev/null | wc -l | tr -d ' ')

say "Inventaire"
printf '  base SQL : %s suite(s)\n' "$SQL_TESTS"
printf '  mobile   : %s fichier(s) _test.dart\n' "$MOBILE_TESTS"

say "Base — migrations, périmètres et escalade"
if ! command -v psql >/dev/null 2>&1; then
  warn "psql absent du PATH — étape ignorée"
  warn "sans elle, les migrations Supabase ne sont pas validées"
else
  bash supabase/tests/verifier-migrations.sh || STATUS=1
fi

say "Mobile"
if [ "$MOBILE_TESTS" = "0" ]; then
  warn "aucun test Flutter"
  printf '    Toute nouvelle fonctionnalité devrait arriver avec les siens :\n'
  printf '    flutter_test, fichiers mobile/test/*_test.dart\n'
elif command -v flutter >/dev/null 2>&1; then
  (cd mobile && flutter test) || STATUS=1
else
  warn "SDK Flutter absent — étape ignorée"
fi

exit $STATUS
