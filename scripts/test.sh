#!/usr/bin/env bash
# Inventaire et exécution des tests du dépôt.
#
# Le projet n'a longtemps eu AUCUN test automatisé, et ce script le disait
# franchement plutôt que de sortir 0 en silence. Depuis la migration 011, il
# existe une suite SQL (database/tests/) qui vérifie par exécution le routage
# des ruptures et la règle d'escalade. Le constat honnête reste valable pour le
# backend et le mobile.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BACKEND_TESTS=$(find backend/src -name '*.spec.ts' 2>/dev/null | wc -l | tr -d ' ')
MOBILE_TESTS=$(find mobile/test -name '*_test.dart' 2>/dev/null | wc -l | tr -d ' ')
SQL_TESTS=$(find database/tests -name '*.sql' 2>/dev/null | wc -l | tr -d ' ')

printf '\n\033[1m▸ Inventaire des tests\033[0m\n'
printf '  backend  : %s fichier(s) .spec.ts\n' "$BACKEND_TESTS"
printf '  mobile   : %s fichier(s) _test.dart\n' "$MOBILE_TESTS"
printf '  base SQL : %s fichier(s) .sql\n' "$SQL_TESTS"

STATUS=0

# ── Tests SQL ───────────────────────────────────────────────────────────────
# Ils ont besoin d'une base provisionnée. Comme les autres scripts du dépôt,
# celui-ci signale et passe quand l'outil manque, pour qu'un environnement
# partiellement provisionné reste utilisable.
if [ "$SQL_TESTS" != "0" ]; then
  printf '\n\033[1m▸ Base — routage des ruptures et escalade\033[0m\n'
  if ! command -v psql >/dev/null 2>&1; then
    printf '  \033[33m! psql absent du PATH — étape ignorée\033[0m\n'
    printf '    Ces tests vérifient le trigger de routage, les deux cercles\n'
    printf '    d.acces et la peremption. Sans eux, la 011 reste non validee.\n'
  elif ! psql -v ON_ERROR_STOP=1 -q -d "${PGDATABASE:-yalla}" -c 'select 1' >/dev/null 2>&1; then
    printf '  \033[33m! base "%s" injoignable — étape ignorée\033[0m\n' "${PGDATABASE:-yalla}"
    printf '    Lancez la commande : npm run db:provision\n'
  else
    for f in database/tests/*.sql; do
      if psql -v ON_ERROR_STOP=1 -q -d "${PGDATABASE:-yalla}" -f "$f" 2>&1 | sed 's/^/    /'; then
        printf '  \033[32m✓ %s\033[0m\n' "$(basename "$f")"
      else
        printf '  \033[31m✗ %s\033[0m\n' "$(basename "$f")"; STATUS=1
      fi
    done
  fi
fi

# ── Backend et mobile ───────────────────────────────────────────────────────
if [ "$BACKEND_TESTS" = "0" ] && [ "$MOBILE_TESTS" = "0" ]; then
  printf '\n\033[33mAucun test automatisé côté backend ni mobile.\033[0m\n'
  printf 'Toute nouvelle fonctionnalité devrait arriver avec ses tests :\n'
  printf '  backend → Jest (@nestjs/testing), fichiers *.spec.ts à côté du service\n'
  printf '  mobile  → flutter_test, fichiers mobile/test/*_test.dart\n\n'
  exit $STATUS
fi

[ "$BACKEND_TESTS" != "0" ] && { npm run test --prefix backend || STATUS=1; }
[ "$MOBILE_TESTS"  != "0" ] && command -v flutter >/dev/null 2>&1 && { (cd mobile && flutter test) || STATUS=1; }
exit $STATUS
