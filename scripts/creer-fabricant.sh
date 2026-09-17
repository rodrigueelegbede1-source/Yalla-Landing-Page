#!/usr/bin/env bash
# Inscrit un fabricant et son catalogue.
#
#   bash scripts/creer-fabricant.sh "Nom du fabricant" 0700000010 catalogue.csv
#
# POURQUOI CETTE ÉTAPE RESTE EN LIGNE DE COMMANDE. Le rôle fabricant n'a pas
# d'interface : il est hors du périmètre du MVP, qui couvre la boucle boutique,
# distributeur, livreur. Recruter un fabricant est d'ailleurs un acte commercial,
# pas une inscription en libre-service, et son catalogue arrive sous forme de
# liste de références, pas saisi une par une sur un téléphone.
#
# CE QUE LE SCRIPT NE CRÉE PAS : de compte de connexion. Le fabricant n'aurait
# rien à consulter. Sa ligne `utilisateurs` existe sans compte `auth`, et le
# rattacher plus tard, quand son tableau de bord existera, se fera par
# `rattacher_compte_auth()`.
#
# LE CATALOGUE se donne en CSV, séparé par des points-virgules, encodé en UTF-8,
# avec une ligne d'en-tête ignorée :
#
#   nom;reference;categorie
#   Sucrerie 33cl;IB-S33;Boissons
#   Eau minérale 1,5L;IB-E15;Boissons
#   Lait concentré 170g;IB-L17;Épicerie
#
# `categorie` doit correspondre à une valeur de `categories_produit` :
# Boissons, Épicerie, Hygiène ou Snacking. Une catégorie inconnue est laissée
# vide plutôt que de faire échouer l'import, et le script le signale.
#
# `reference` est la référence interne du fabricant, celle imprimée sur le
# carton. Elle doit être unique chez lui : c'est par elle que le distributeur
# retrouve un produit dans un bon de livraison.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NOM="${1:-}"
TEL_BRUT="${2:-}"
CSV="${3:-}"

if [ -z "$NOM" ] || [ -z "$TEL_BRUT" ] || [ -z "$CSV" ]; then
  echo
  echo "  Usage : bash scripts/creer-fabricant.sh \"Nom\" <telephone> <catalogue.csv>"
  echo
  echo "  Exemple :"
  echo "    bash scripts/creer-fabricant.sh \"Ivoire Boissons\" 0700000010 catalogue.csv"
  echo
  echo "  Le CSV attend : nom;reference;categorie   (une ligne d'en-tête, ignorée)"
  echo "  Catégories acceptées : Boissons, Épicerie, Hygiène, Snacking"
  exit 1
fi

[ -f "$CSV" ] || { echo "  Fichier introuvable : $CSV"; exit 1; }

ENV_FICHIER="${YALLA_ENV:-$HOME/Downloads/jarvis-starter-kit/.env}"
lire() {
  grep -E "^$1=" "$ENV_FICHIER" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'"' \r'
}

URL="$(lire SUPABASE_URL)"
MDP_BASE="$(lire SUPABASE_DB_PASSWORD)"
REF_PROJET="$(printf '%s' "$URL" | sed 's|https://||; s|\.supabase\.co.*||')"

[ -n "$REF_PROJET" ] || { echo "  SUPABASE_URL absente de $ENV_FICHIER"; exit 1; }
[ -n "$MDP_BASE" ]   || { echo "  SUPABASE_DB_PASSWORD absente de $ENV_FICHIER"; exit 1; }

CONNEXION="postgresql://postgres.$REF_PROJET@aws-1-eu-west-3.pooler.supabase.com:5432/postgres"
export PGPASSWORD="$MDP_BASE"

# Même normalisation qu'en SQL, en Dart et dans la fonction Edge.
normaliser() {
  local v="${1//[^0-9]/}"
  if [ "${v:0:5}" = "00225" ]; then v="${v:2}"; fi
  if [ "${#v}" = "10" ] && [ "${v:0:1}" = "0" ]; then v="225$v"; fi
  printf '%s' "$v"
}

TEL="$(normaliser "$TEL_BRUT")"
if [ "${#TEL}" != 13 ]; then
  echo "  Numéro invalide : $TEL_BRUT (attendu 10 chiffres, ex. 0700000010)"
  exit 1
fi

echappe() { printf '%s' "$1" | sed "s/'/''/g"; }

# Le CSV devient une série de VALUES. On ignore l'en-tête et les lignes vides,
# et on tolère un CRLF, que produisent tous les tableurs sous Windows.
VALEURS=""
LIGNE_NUM=0
IGNOREES=0
while IFS= read -r ligne || [ -n "$ligne" ]; do
  LIGNE_NUM=$((LIGNE_NUM + 1))
  ligne="${ligne%$'\r'}"
  [ "$LIGNE_NUM" = "1" ] && continue      # en-tête
  [ -z "${ligne// /}" ] && continue        # ligne vide

  IFS=';' read -r p_nom p_ref p_cat <<< "$ligne"
  p_nom="$(printf '%s' "$p_nom" | sed 's/^ *//; s/ *$//')"
  p_ref="$(printf '%s' "$p_ref" | sed 's/^ *//; s/ *$//')"
  p_cat="$(printf '%s' "$p_cat" | sed 's/^ *//; s/ *$//')"

  if [ -z "$p_nom" ] || [ -z "$p_ref" ]; then
    echo "  ligne $LIGNE_NUM ignorée : nom ou référence manquant"
    IGNOREES=$((IGNOREES + 1))
    continue
  fi

  [ -n "$VALEURS" ] && VALEURS="$VALEURS,"
  VALEURS="$VALEURS
    ('$(echappe "$p_nom")', '$(echappe "$p_ref")', $(
      if [ -z "$p_cat" ]; then printf 'NULL'; else printf "'%s'" "$(echappe "$p_cat")"; fi
    ))"
done < "$CSV"

if [ -z "$VALEURS" ]; then
  echo "  Aucun produit lisible dans $CSV"
  exit 1
fi

echo
echo "Inscription de « $NOM » sur $REF_PROJET"
echo

# Tout dans une transaction : un fabricant sans catalogue ne sert à rien, et un
# catalogue sans fabricant est impossible. L'un ou l'autre échoue, rien n'est écrit.
psql "$CONNEXION" -w -v ON_ERROR_STOP=1 <<SQL
BEGIN;

DO \$bloc\$
DECLARE
  v_u   UUID;
  v_fab UUID;
  v_inconnues TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM utilisateurs WHERE telephone = '$TEL') THEN
    RAISE EXCEPTION 'Le numéro $TEL est déjà rattaché à un compte Yalla';
  END IF;

  -- Pas de auth_user_id : le fabricant n'a rien à consulter pour l'instant.
  INSERT INTO utilisateurs (nom, telephone, role)
  VALUES ('$(echappe "$NOM")', '$TEL', 'fabricant')
  RETURNING id INTO v_u;

  INSERT INTO fabricants (utilisateur_id, nom)
  VALUES (v_u, '$(echappe "$NOM")')
  RETURNING id INTO v_fab;

  -- Les catégories sont jointes par leur nom. Une catégorie inconnue donne un
  -- produit sans catégorie plutôt qu'un import en échec : mieux vaut un
  -- catalogue complet mal classé qu'une commande qui refuse tout.
  WITH entrees(nom, reference, categorie) AS (VALUES $VALEURS)
  INSERT INTO produits (fabricant_id, nom, reference, categorie_id)
  SELECT v_fab, e.nom, e.reference, c.id
    FROM entrees e
    LEFT JOIN categories_produit c ON c.nom = e.categorie;

  SELECT string_agg(DISTINCT e.categorie, ', ')
    INTO v_inconnues
    FROM (VALUES $VALEURS) AS e(nom, reference, categorie)
   WHERE e.categorie IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM categories_produit c WHERE c.nom = e.categorie);

  IF v_inconnues IS NOT NULL THEN
    RAISE WARNING 'Catégories inconnues, produits laissés sans catégorie : %', v_inconnues;
  END IF;
END;
\$bloc\$;

COMMIT;

SELECT f.nom AS fabricant, count(p.id) AS produits
  FROM fabricants f LEFT JOIN produits p ON p.fabricant_id = f.id
 WHERE f.nom = '$(echappe "$NOM")'
 GROUP BY f.nom;

SELECT p.nom, p.reference, COALESCE(c.nom, '(sans catégorie)') AS categorie
  FROM produits p
  JOIN fabricants f ON f.id = p.fabricant_id
  LEFT JOIN categories_produit c ON c.id = p.categorie_id
 WHERE f.nom = '$(echappe "$NOM")'
 ORDER BY p.reference;
SQL

# PostgREST garde en cache le schéma, pas les données : inutile de le recharger
# ici. En revanche les distributeurs doivent maintenant revendiquer les
# boutiques pour cette marque, sans quoi ses ruptures partiront sans adresse.
echo
echo "Fabricant inscrit."
if [ "$IGNOREES" != "0" ]; then
  echo "$IGNOREES ligne(s) du CSV ignorée(s), voir ci-dessus."
fi
echo
echo "ÉTAPE SUIVANTE, sans laquelle le routage ne marche pas : chaque"
echo "distributeur doit revendiquer ses boutiques pour cette marque, depuis"
echo "l'onglet Réseau de l'application. Une boutique non revendiquée produit"
echo "des ruptures sans destinataire, invisibles pendant deux heures."
echo
