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

say "Scripts — ordre des arguments de psql"
# LE PIÈGE, ET POURQUOI IL MÉRITE SON PROPRE CONTRÔLE. Le `getopt` livré avec
# PostgreSQL sous Windows ne réordonne pas les arguments : il s'arrête au
# premier qui n'est pas une option. Écrire `psql "$CONNEXION" -w -c "..."`
# revient donc à passer l'URL comme base de données puis à JETER tout le reste,
# `-c` et sa requête compris. psql écrit « option supplémentaire ignorée » sur
# la sortie d'erreur et sort avec le code 0.
#
# Conséquence : la commande ne fait rien, le script croit avoir réussi, et
# `set -e` ne voit rien passer. Trouvé sur huit appels dans quatre scripts, dont
# un qui annonçait « cache rechargé » sans avoir rien rechargé et un autre qui
# répondait « rien à faire » sur une liste qu'il n'avait jamais lue.
#
# La règle est donc simple : les options d'abord, la chaîne de connexion en
# dernier. Ce contrôle la fait respecter.
#
# Les lignes de commentaire sont écartées, sans quoi ce contrôle se déclenche
# sur l'exemple fautif écrit juste au-dessus. C'est arrivé à la première
# exécution.
FAUTIFS="$(grep -rn 'psql "\$[A-Z_]*" \+-' scripts/ supabase/tests/ 2>/dev/null \
  | grep -v ':[[:space:]]*#' | cut -d: -f1 | sort -u || true)"
if [ -n "$FAUTIFS" ]; then
  ko "options passées après la chaîne de connexion, elles seront ignorées :"
  printf '%s\n' "$FAUTIFS" | sed 's/^/      /'
  STATUS=1
else
  ok "les options précèdent partout la chaîne de connexion"
fi

say "Landing — syntaxe JavaScript"
# TOUS les fichiers du dossier, pas une liste écrite à la main. La liste en dur
# n'en couvrait que deux sur huit : les tableaux de bord, ajoutés plus tard,
# n'étaient pas vérifiés du tout, et une coquille n'y serait apparue qu'à
# l'ouverture de la page par un utilisateur.
#
# `config.js` est exclu : il est généré au déploiement et absent du dépôt, donc
# son absence ne doit pas faire échouer le lint.
if command -v node >/dev/null 2>&1; then
  for f in landing/*.js; do
    [ "$(basename "$f")" = "config.js" ] && continue
    if node --check "$f" 2>/dev/null; then
      ok "$(basename "$f") valide"
    else
      ko "$(basename "$f") invalide"; STATUS=1
      node --check "$f" 2>&1 | sed 's/^/      /' | head -4
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
