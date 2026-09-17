#!/usr/bin/env bash
# Écrit `mobile/android/key.properties` à partir du `.env`, pour que l'APK de
# production soit signé par la vraie clé et non par celle de débogage.
#
#   bash scripts/preparer-signature.sh
#
# POURQUOI CE DÉTOUR PLUTÔT QU'UN FICHIER COMMITÉ. Gradle veut les chemins et
# les mots de passe dans un fichier de propriétés. Ce fichier contient un secret,
# il ne peut donc pas entrer dans le dépôt, et il est ignoré par Git. Ce script
# le reconstruit depuis le `.env`, seul endroit où vivent les secrets.
#
# CE QU'IL NE FAUT PAS PERDRE. Android identifie une application par le couple
# (identifiant, signature). Perdre `yalla-release.jks` ou son mot de passe rend
# toute mise à jour impossible sur les téléphones où l'application est déjà
# installée : il faudrait désinstaller chez chaque boutiquier, en effaçant ses
# données. Sauvegardez le fichier ailleurs que sur cette machine.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FICHIER="${YALLA_ENV:-$HOME/Downloads/jarvis-starter-kit/.env}"

lire() {
  grep -E "^$1=" "$ENV_FICHIER" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'"' \r'
}

KEYSTORE="$(lire YALLA_KEYSTORE)"
MDP="$(lire YALLA_KEYSTORE_PASSWORD)"
ALIAS="$(lire YALLA_KEYSTORE_ALIAS)"

if [ -z "$KEYSTORE" ] || [ -z "$MDP" ] || [ -z "$ALIAS" ]; then
  echo "  YALLA_KEYSTORE, YALLA_KEYSTORE_PASSWORD ou YALLA_KEYSTORE_ALIAS manque"
  echo "  dans $ENV_FICHIER."
  echo
  echo "  Pour créer une clé neuve (une seule fois, à conserver 30 ans) :"
  echo
  echo "    keytool -genkeypair -v -keystore ~/.yalla-cles/yalla-release.jks \\"
  echo "      -keyalg RSA -keysize 4096 -validity 10950 -alias yalla \\"
  echo "      -dname \"CN=Yalla, OU=Elegson, O=Elegson, L=Abidjan, C=CI\""
  exit 1
fi

# Chemin au format attendu par Gradle, y compris sous Windows.
CHEMIN_WIN="$(printf '%s' "$KEYSTORE" | sed 's|\\|/|g')"

if [ ! -f "$CHEMIN_WIN" ] && [ ! -f "$(printf '%s' "$CHEMIN_WIN" | sed 's|^\([A-Za-z]\):|/\1|')" ]; then
  echo "  Fichier de clé introuvable : $KEYSTORE"
  echo "  Sans lui, aucune mise à jour n'est possible sur les téléphones déjà équipés."
  exit 1
fi

cat > "$ROOT/mobile/android/key.properties" <<PROPS
# Généré par scripts/preparer-signature.sh depuis le .env.
# Contient un secret : ce fichier est ignoré par Git et ne doit jamais être commité.
storeFile=$CHEMIN_WIN
storePassword=$MDP
keyAlias=$ALIAS
keyPassword=$MDP
PROPS

echo "  mobile/android/key.properties écrit."
echo "  L'APK de production sera signé par la clé Yalla."
