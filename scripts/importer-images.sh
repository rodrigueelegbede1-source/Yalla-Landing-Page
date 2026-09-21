#!/usr/bin/env bash
# Charge les photos de produits dans Supabase Storage et les rattache au
# catalogue.
#
#   bash scripts/importer-images.sh catalogues/images-sdtm/
#
# Le dossier contient une image par produit, nommée d'après sa RÉFÉRENCE :
#
#   SDTM-TOM400.jpg
#   SDTM-RIZBA900.png
#   SDTM-SAVVAN400.webp
#
# C'est la référence et non le nom qui sert de clé : elle est déjà unique par
# fabricant, elle ne contient ni accent ni espace, et elle figure sur le carton,
# donc celui qui photographie les produits sait quoi taper.
#
# ── POURQUOI STOCKER PLUTÔT QUE POINTER ─────────────────────────────────────
#
# Il serait plus rapide d'enregistrer l'adresse d'une image hébergée ailleurs.
# Deux raisons de ne pas le faire :
#
#   * une adresse externe casse sans prévenir, et le jour où elle casse c'est
#     tout le catalogue qui devient illisible sur le terrain ;
#   * ces images appartiennent au fabricant. Les servir depuis son site sans
#     son accord, c'est utiliser sa bande passante sans le lui demander.
#     Les héberger suppose qu'il les a fournies, ce qui règle la question.
#
# ── CE QU'IL FAUT DEMANDER AU FABRICANT ─────────────────────────────────────
#
# Ses packshots, ceux qu'il donne déjà à ses distributeurs et aux enseignes.
# Format carré de préférence, fond neutre, 600 px de côté suffisent largement :
# l'image est affichée dans une vignette de 44 px sur un téléphone d'entrée de
# gamme, et une photo de 4 Mo ne ferait que vider le forfait du boutiquier.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOSSIER="${1:-}"

if [ -z "$DOSSIER" ] || [ ! -d "$DOSSIER" ]; then
  echo
  echo "  Usage : bash scripts/importer-images.sh <dossier>"
  echo
  echo "  Le dossier contient une image par produit, nommée d'après sa"
  echo "  référence : SDTM-TOM400.jpg, SDTM-RIZ900.png, ..."
  echo
  echo "  Les références se listent ainsi :"
  echo "    psql \"\$CONNEXION\" -c \"SELECT reference, nom FROM produits ORDER BY reference\""
  exit 1
fi

ENV_FICHIER="${YALLA_ENV:-$HOME/Downloads/jarvis-starter-kit/.env}"
lire() {
  grep -E "^$1=" "$ENV_FICHIER" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'"' \r'
}

URL="$(lire SUPABASE_URL)"
CLE_SERVICE="$(lire SUPABASE_SERVICE_ROLE_KEY)"
MDP_BASE="$(lire SUPABASE_DB_PASSWORD)"
REF_PROJET="$(printf '%s' "$URL" | sed 's|https://||; s|\.supabase\.co.*||')"

[ -n "$URL" ]         || { echo "  SUPABASE_URL absente de $ENV_FICHIER"; exit 1; }
[ -n "$CLE_SERVICE" ] || { echo "  SUPABASE_SERVICE_ROLE_KEY absente de $ENV_FICHIER"; exit 1; }
[ -n "$MDP_BASE" ]    || { echo "  SUPABASE_DB_PASSWORD absente de $ENV_FICHIER"; exit 1; }

command -v psql >/dev/null 2>&1 || { echo "  psql introuvable dans le PATH"; exit 1; }

CONNEXION="postgresql://postgres.$REF_PROJET@aws-1-eu-west-3.pooler.supabase.com:5432/postgres"
export PGPASSWORD="$MDP_BASE"

echo
echo "Import des images depuis $DOSSIER"
echo

CHARGEES=0
INCONNUES=0
ECHECS=0

for fichier in "$DOSSIER"/*; do
  [ -f "$fichier" ] || continue

  base="$(basename "$fichier")"
  reference="${base%.*}"
  extension="${base##*.}"

  case "$(printf '%s' "$extension" | tr '[:upper:]' '[:lower:]')" in
    jpg|jpeg) type_mime="image/jpeg" ;;
    png)      type_mime="image/png" ;;
    webp)     type_mime="image/webp" ;;
    *)        echo "  ⊘ $base : format non pris en charge"; INCONNUES=$((INCONNUES + 1)); continue ;;
  esac

  # La référence doit exister, sinon l'image serait chargée pour rien et
  # personne ne s'en apercevrait.
  # `tr -d '\r'` : sous Windows psql termine ses lignes par CRLF, et « 0 »
  # comparé à « 0\r » n'est jamais égal. Sans cette purge, toute référence
  # absente du catalogue passerait pour présente.
  if [ "$(psql -w -tAc "SELECT count(*) FROM produits WHERE reference = '$(printf '%s' "$reference" | sed "s/'/''/g")'" "$CONNEXION" | tr -d '\r')" = "0" ]; then
    echo "  ⊘ $base : aucune référence « $reference » au catalogue"
    INCONNUES=$((INCONNUES + 1))
    continue
  fi

  chemin="produits/$reference.$extension"

  # `x-upsert` pour que réimporter une image corrigée remplace l'ancienne au
  # lieu d'échouer : les premiers packshots sont souvent à refaire.
  code="$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST "$URL/storage/v1/object/$chemin" \
    -H "apikey: $CLE_SERVICE" \
    -H "Authorization: Bearer $CLE_SERVICE" \
    -H "Content-Type: $type_mime" \
    -H "x-upsert: true" \
    --data-binary "@$fichier")"

  if [ "$code" != "200" ] && [ "$code" != "201" ]; then
    echo "  ✗ $base : envoi refusé (HTTP $code)"
    ECHECS=$((ECHECS + 1))
    continue
  fi

  psql -w -q -c "
    UPDATE produits
       SET image_url = '$URL/storage/v1/object/public/$chemin'
     WHERE reference = '$(printf '%s' "$reference" | sed "s/'/''/g")'" "$CONNEXION"

  echo "  ✓ $reference"
  CHARGEES=$((CHARGEES + 1))
done

echo
echo "$CHARGEES image(s) rattachée(s)."
[ "$INCONNUES" != "0" ] && echo "$INCONNUES fichier(s) ignoré(s), voir ci-dessus."
[ "$ECHECS" != "0" ]    && echo "$ECHECS envoi(s) en échec."

echo
psql -w -c "
  SELECT f.nom AS fabricant,
         count(*) FILTER (WHERE p.image_url IS NOT NULL) AS avec_image,
         count(*) AS total
    FROM produits p JOIN fabricants f ON f.id = p.fabricant_id
   GROUP BY f.nom ORDER BY f.nom" "$CONNEXION"

echo "Les produits sans image gardent leur vignette : initiales du produit sur"
echo "une couleur tirée de la catégorie. L'écran reste lisible sans photo."
echo
