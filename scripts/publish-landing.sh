#!/usr/bin/env bash
# Publie la landing en ligne.
#
#   npm run publish:landing
#
# Le site public est servi par GitHub Pages depuis le dépôt public
# `Yalla-Landing-Page`, qui n'est qu'un miroir du dossier `landing/` de ce dépôt.
# Ce détour existe parce que GitHub Pages n'est pas disponible sur un dépôt privé
# avec un compte Free, et que ce dépôt-ci doit rester privé. Le miroir ne contient
# que la landing, c'est-à-dire du contenu déjà public par nature.
#
# `landing/` reste la SOURCE UNIQUE. Ce script régénère le miroir à partir d'elle
# et l'écrase. Toute modification faite directement sur le miroir sera perdue.
#
# Le script ne publie que si le dossier landing/ est propre et commité : publier
# un état non commité rendrait le site impossible à reconstituer depuis l'historique.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MIROIR="https://github.com/rodrigueelegbede1-source/Yalla-Landing-Page.git"
SITE="https://rodrigueelegbede1-source.github.io/Yalla-Landing-Page/"

say() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
ok()  { printf '  \033[32m✓ %s\033[0m\n' "$1"; }
die() { printf '  \033[31m✗ %s\033[0m\n' "$1"; exit 1; }

command -v git >/dev/null 2>&1 || die "git introuvable dans le PATH"

say "Vérifications"
if [ -n "$(git status --porcelain -- landing 2>/dev/null)" ]; then
  git status --short -- landing | sed 's/^/    /'
  die "landing/ contient des modifications non commitées — commitez-les d'abord"
fi
ok "landing/ est propre"

BRANCHE="$(git rev-parse --abbrev-ref HEAD)"

say "Régénération du miroir depuis landing/"
git branch -D gh-pages >/dev/null 2>&1 || true
SHA="$(git subtree split --prefix landing -b gh-pages 2>/dev/null | tail -1)"
[ -n "$SHA" ] || die "échec de l'extraction de landing/"
ok "miroir régénéré (${SHA:0:7})"

say "Publication"
git push -f origin gh-pages >/dev/null 2>&1 && ok "branche gh-pages poussée sur le dépôt privé" \
  || printf '  \033[33m! gh-pages non poussée sur origin (sans conséquence pour le site)\033[0m\n'

if git push -f "$MIROIR" gh-pages:main 2>/dev/null; then
  ok "miroir public mis à jour"
else
  die "échec de la publication vers le miroir — vérifiez 'gh auth status'"
fi

git checkout "$BRANCHE" >/dev/null 2>&1

say "Résultat"
printf '  GitHub Pages reconstruit le site en une à deux minutes.\n'
printf '  \033[1m%s\033[0m\n\n' "$SITE"
printf '  Suivi de la construction :\n'
printf '    gh api repos/rodrigueelegbede1-source/Yalla-Landing-Page/pages/builds/latest --jq .status\n\n'
