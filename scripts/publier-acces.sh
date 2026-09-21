#!/usr/bin/env bash
# Écrit `landing/config.js` depuis le .env, avant tout déploiement du site.
#
#   bash scripts/publier-acces.sh
#
# POURQUOI UN FICHIER GÉNÉRÉ PLUTÔT QU'UNE VALEUR ÉCRITE DANS LE JS.
#
# L'espace professionnel appelle Supabase depuis le navigateur, il lui faut donc
# l'adresse du projet et la clé publiable dans une page servie en clair. Cette
# clé est publique par conception, exactement comme celle qu'un APK décompilé
# révèle : ce n'est pas elle qui protège les données, ce sont les politiques RLS.
#
# Elle n'a pour autant rien à faire écrite à la main dans le dépôt. Une clé
# recopiée de mémoire est une clé fausse, et l'erreur ne se voit qu'au premier
# visiteur qui essaie de se connecter. C'est exactement ce qui s'est produit en
# écrivant `acces.js` la première fois.
#
# `config.js` est donc ignoré par Git et régénéré depuis la seule source de
# vérité, le `.env` de l'espace de travail.
#
# LA CLÉ DE SERVICE N'ENTRE JAMAIS ICI. Elle contourne RLS, et une page web la
# livrerait au premier venu.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FICHIER="${YALLA_ENV:-$HOME/Downloads/jarvis-starter-kit/.env}"

lire() {
  grep -E "^$1=" "$ENV_FICHIER" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'"' \r'
}

URL="$(lire SUPABASE_URL)"
CLE="$(lire SUPABASE_ANON_KEY)"

if [ -z "$URL" ] || [ -z "$CLE" ]; then
  echo "  SUPABASE_URL ou SUPABASE_ANON_KEY manque dans $ENV_FICHIER"
  exit 1
fi

# Garde-fou : la clé de service ne doit jamais se retrouver ici, même par une
# erreur de copie dans le .env. Elle commence par `sb_secret` ou porte le rôle
# `service_role` dans un JWT.
case "$CLE" in
  sb_secret*|*service_role*)
    echo "  SUPABASE_ANON_KEY contient une clé de SERVICE."
    echo "  Elle contourne RLS et ne doit jamais entrer dans une page web."
    exit 1
    ;;
esac

cat > "$ROOT/landing/config.js" <<CONFIG
/* Généré par scripts/publier-acces.sh. Ne pas modifier à la main, ne pas commiter.
   La clé publiable est publique par conception : ce sont les politiques RLS qui
   protègent les données, jamais elle. */
window.YALLA_CONFIG = {
  url: '$URL',
  cle: '$CLE',
};
CONFIG

echo "  landing/config.js écrit pour $URL"
echo "  Clé publiable : ${CLE:0:18}…"
