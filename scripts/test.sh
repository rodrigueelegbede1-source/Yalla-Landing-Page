#!/usr/bin/env bash
# Le projet n'a AUCUN test automatisé à ce jour.
# Ce script le dit franchement plutôt que de sortir 0 en silence, ce qui
# laisserait croire à une suite verte inexistante.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BACKEND_TESTS=$(find backend/src -name '*.spec.ts' 2>/dev/null | wc -l | tr -d ' ')
MOBILE_TESTS=$(find mobile/test -name '*_test.dart' 2>/dev/null | wc -l | tr -d ' ')

printf '\n\033[1m▸ Inventaire des tests\033[0m\n'
printf '  backend : %s fichier(s) .spec.ts\n' "$BACKEND_TESTS"
printf '  mobile  : %s fichier(s) _test.dart\n' "$MOBILE_TESTS"

if [ "$BACKEND_TESTS" = "0" ] && [ "$MOBILE_TESTS" = "0" ]; then
  printf '\n\033[33mAucun test automatisé dans ce dépôt.\033[0m\n'
  printf 'Toute nouvelle fonctionnalité devrait arriver avec ses tests :\n'
  printf '  backend → Jest (@nestjs/testing), fichiers *.spec.ts à côté du service\n'
  printf '  mobile  → flutter_test, fichiers mobile/test/*_test.dart\n\n'
  exit 0
fi

STATUS=0
[ "$BACKEND_TESTS" != "0" ] && { npm run test --prefix backend || STATUS=1; }
[ "$MOBILE_TESTS"  != "0" ] && command -v flutter >/dev/null 2>&1 && { (cd mobile && flutter test) || STATUS=1; }
exit $STATUS
