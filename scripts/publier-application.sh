#!/usr/bin/env bash
# Compile l'APK de production et le met en ligne pour téléchargement.
#
#   bash scripts/publier-application.sh
#
# ── DEUX CHOIX QUI ONT COÛTÉ CHER À TROUVER ────────────────────────────────
#
# 1. `--target-platform android-arm,android-arm64`, et non un APK universel.
#
#    Un APK universel embarque le moteur Flutter compilé pour chaque
#    architecture. En incluant x86_64, qui ne sert qu'aux émulateurs, le fichier
#    passe de 36 à 57 Mo : vingt mégaoctets de données facturées au boutiquier
#    pour du code qu'aucun téléphone n'exécutera. C'est aussi ce qui le faisait
#    dépasser la limite de l'hébergement.
#
#    À noter : les `abiFilters` du NDK dans build.gradle.kts ne suffisent PAS.
#    Ils filtrent les bibliothèques du NDK, pas celles que Flutter copie
#    lui-même. Seule cette option agit sur la taille.
#
# 2. Le daemon Gradle est limité à 4 Go dans `gradle.properties`.
#
#    Avec les 8 Go par défaut, la JVM tombait en « insufficient memory for the
#    Java Runtime Environment » dès qu'un émulateur tournait en parallèle. Le
#    message remonté par Flutter ne disait que « Gradle task assembleRelease
#    failed », sans jamais mentionner la mémoire. Si un build échoue sans raison
#    apparente, fermez l'émulateur avant de chercher ailleurs.
#
# ── POURQUOI SUPABASE STORAGE PLUTÔT QUE LE SITE ───────────────────────────
#
# Un binaire de 36 Mo dans le dépôt Git serait retransféré à chaque déploiement
# du site, et Git n'est pas fait pour versionner des binaires. Le fichier vit
# donc dans un compartiment public de Supabase, et la page de téléchargement
# pointe dessus.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FICHIER="${YALLA_ENV:-$HOME/Downloads/jarvis-starter-kit/.env}"

lire() {
  grep -E "^$1=" "$ENV_FICHIER" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'"' \r'
}

URL="$(lire SUPABASE_URL)"
CLE_PUB="$(lire SUPABASE_ANON_KEY)"
CLE_SERVICE="$(lire SUPABASE_SERVICE_ROLE_KEY)"

[ -n "$URL" ]         || { echo "  SUPABASE_URL absente de $ENV_FICHIER"; exit 1; }
[ -n "$CLE_PUB" ]     || { echo "  SUPABASE_ANON_KEY absente de $ENV_FICHIER"; exit 1; }
[ -n "$CLE_SERVICE" ] || { echo "  SUPABASE_SERVICE_ROLE_KEY absente de $ENV_FICHIER"; exit 1; }

command -v flutter >/dev/null 2>&1 || { echo "  flutter introuvable dans le PATH"; exit 1; }

if [ -f "$ROOT/mobile/android/key.properties" ]; then
  echo "  Signature de production détectée."
else
  echo
  echo "  ERREUR : mobile/android/key.properties est absent."
  echo "  Aucun APK ne sera produit sans la clé permanente de production."
  echo "  Lancez d'abord : bash scripts/preparer-signature.sh"
  exit 1
fi

echo
echo "▸ Compilation"
cd "$ROOT/mobile"
flutter build apk --release \
  --target-platform android-arm,android-arm64 \
  --dart-define=SUPABASE_URL="$URL" \
  --dart-define=SUPABASE_ANON_KEY="$CLE_PUB"

APK="$ROOT/mobile/build/app/outputs/flutter-apk/app-release.apk"
[ -f "$APK" ] || { echo "  APK introuvable après compilation"; exit 1; }

if command -v apksigner >/dev/null 2>&1; then
  apksigner verify --verbose "$APK" >/dev/null || {
    echo "  Signature APK invalide"; exit 1;
  }
  echo "  Signature APK vérifiée."
else
  echo "  ATTENTION : apksigner absent, signature non vérifiée automatiquement."
fi

TAILLE=$(( $(wc -c < "$APK") / 1048576 ))
echo "  APK : ${TAILLE} Mo"

# La limite du plan est de 50 Mo par fichier. Vérifier ici évite un envoi de
# plusieurs minutes qui finit en « Payload too large ».
if [ "$TAILLE" -gt 49 ]; then
  echo
  echo "  L'APK dépasse la limite d'hébergement de 50 Mo."
  echo "  Vérifiez que --target-platform est bien appliqué : un APK universel"
  echo "  inclut x86_64 et atteint 57 Mo."
  exit 1
fi

echo
echo "▸ Mise en ligne"
CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  -X POST "$URL/storage/v1/object/application/yalla.apk" \
  -H "apikey: $CLE_SERVICE" \
  -H "Authorization: Bearer $CLE_SERVICE" \
  -H "Content-Type: application/vnd.android.package-archive" \
  -H "x-upsert: true" \
  --data-binary "@$APK")

if [ "$CODE" != "200" ] && [ "$CODE" != "201" ]; then
  echo "  Envoi refusé (HTTP $CODE)"
  exit 1
fi

echo "  En ligne : $URL/storage/v1/object/public/application/yalla.apk"
echo
echo "La page de téléchargement lit la taille du fichier à chaque visite :"
echo "elle affichera d'elle-même la nouvelle version, sans rien à modifier."
echo
