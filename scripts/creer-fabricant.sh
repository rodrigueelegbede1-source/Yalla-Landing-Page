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
# CE QUE LE SCRIPT NE CRÉE PAS : de compte de connexion. Sa ligne
# `utilisateurs` existe sans compte `auth`.
#
# C'était sans conséquence tant que le fabricant n'avait aucun écran : un compte
# l'aurait laissé devant une page vide. Son tableau de bord existe depuis le
# 21/09/2026, et l'omission est devenue un blocage muet. Rien ne la signale,
# puisque la marque, le catalogue et les ruptures existent parfaitement en
# base ; elle ne se voit qu'en essayant de se connecter, c'est-à-dire devant le
# client.
#
#   ENCHAÎNEZ DONC TOUJOURS SUR :
#     bash scripts/ouvrir-compte-fabricant.sh "Nom de la marque"
#
# LE CATALOGUE se donne en CSV, séparé par des points-virgules, encodé en UTF-8,
# avec une ligne d'en-tête ignorée :
#
#   nom;reference;categorie
#   Sucrerie 33cl;;Boissons
#   Eau minérale 1,5L;;Boissons
#   Lait concentré 170g;IB-L17;Épicerie
#
# `categorie` doit correspondre à une valeur de `categories_produit` :
# Boissons, Épicerie, Hygiène ou Snacking. Une catégorie inconnue est laissée
# vide plutôt que de faire échouer l'import, et le script le signale.
#
# `reference` EST FACULTATIVE. Laissée vide, elle est générée depuis le nom de
# la marque et celui du produit, ce qui évite d'attendre la nomenclature du
# fabricant pour commencer à recenser. Une référence fournie est reprise telle
# quelle : les deux se mélangent sans difficulté dans le même fichier.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NOM="${1:-}"
TEL_BRUT="${2:-}"
CSV="${3:-}"
# Préfixe de référence imposé, facultatif. Utile quand la raison sociale ne
# donne pas d'initiales lisibles : « Société de Distribution de Toutes
# Marchandises (SDTM-CI) » produirait « SDD », que personne ne rattacherait à
# la marque, alors que « SDTM » se reconnaît immédiatement sur un bon.
PREFIXE_IMPOSE="${4:-}"

if [ -z "$NOM" ] || [ -z "$TEL_BRUT" ] || [ -z "$CSV" ]; then
  echo
  echo "  Usage : bash scripts/creer-fabricant.sh \"Nom\" <telephone> <catalogue.csv> [prefixe]"
  echo
  echo "  Exemples :"
  echo "    bash scripts/creer-fabricant.sh \"Ivoire Boissons\" 0700000010 catalogue.csv"
  echo "    bash scripts/creer-fabricant.sh \"SDTM-CI\" 2721219000 catalogue.csv SDTM"
  echo
  echo "  Le préfixe est déduit du nom s'il n'est pas donné. Imposez-le quand la"
  echo "  raison sociale ne donne pas d'initiales reconnaissables."
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
  # Dix chiffres = numéro national, quel que soit le premier chiffre : les
  # mobiles commencent par 01, 05 ou 07, les fixes par 25 ou 27.
  if [ "${#v}" = "10" ]; then v="225$v"; fi
  printf '%s' "$v"
}

TEL="$(normaliser "$TEL_BRUT")"
if [ "${#TEL}" != 13 ]; then
  echo "  Numéro invalide : $TEL_BRUT (attendu 10 chiffres, ex. 0700000010)"
  exit 1
fi

echappe() { printf '%s' "$1" | sed "s/'/''/g"; }

# ── Génération des références ───────────────────────────────────────────────
#
# La colonne `reference` du CSV est facultative. Laissée vide, elle est
# fabriquée ici, parce qu'au stade du pilote on n'a généralement pas la
# nomenclature du fabricant sous la main, et l'attendre bloquerait le
# recensement pour rien.
#
# LE CRITÈRE N'EST PAS L'UNICITÉ, C'EST LA LISIBILITÉ. Un identifiant
# aléatoire serait unique et inutilisable : cette référence sert au
# distributeur à retrouver un produit sur un bon de livraison, souvent écrit à
# la main, parfois lu au téléphone dans le bruit d'un marché. Elle doit donc se
# dire à voix haute et se reconnaître d'un coup d'œil.
#
# Forme retenue : PRÉFIXE-LLLNNN
#   * PRÉFIXE : les initiales de la marque, ou ses trois premières lettres si
#     elle n'a qu'un mot. « Ivoire Boissons » donne IB, « Solibra » donne SOL.
#   * LLL : les trois premières lettres du premier mot du produit.
#   * NNN : les chiffres du nom, qui portent presque toujours le format. C'est
#     ce qui distingue une sucrerie 33 cl d'une 50 cl, et c'est exactement la
#     confusion qu'un livreur doit pouvoir éviter.
#
# « Sucrerie 33cl » chez Ivoire Boissons donne donc IB-SUC33.

# Le remplacement natif de bash, et non `sed y/.../.../` ni `iconv //TRANSLIT`.
#
# `sed y` compte les OCTETS : un accent UTF-8 en faisant deux, les deux chaînes
# de la commande n'ont jamais la même longueur et sed refuse de s'exécuter.
# `iconv //TRANSLIT` rend « concentré » sous la forme « concentr'e », et
# l'apostrophe ajoutée casse le mot au filtrage suivant. Le remplacement de
# sous-chaîne de bash, lui, cherche la séquence d'octets entière et fait ce
# qu'on attend.
sans_accents() {
  local v="$1"
  # Un remplacement PAR CARACTÈRE, jamais par classe `[éèêë]`. Une classe de
  # caractères est interprétée octet par octet : « é » valant 0xC3 0xA9, chacun
  # de ses deux octets est remplacé séparément et « Thé » devient « Thee ».
  # Le remplacement d'une sous-chaîne littérale, lui, cherche la séquence
  # entière et se comporte correctement.
  v="${v//à/a}"; v="${v//â/a}"; v="${v//ä/a}"; v="${v//á/a}"; v="${v//ã/a}"; v="${v//å/a}"
  v="${v//é/e}"; v="${v//è/e}"; v="${v//ê/e}"; v="${v//ë/e}"
  v="${v//í/i}"; v="${v//ì/i}"; v="${v//î/i}"; v="${v//ï/i}"
  v="${v//ó/o}"; v="${v//ò/o}"; v="${v//ô/o}"; v="${v//ö/o}"; v="${v//õ/o}"
  v="${v//ú/u}"; v="${v//ù/u}"; v="${v//û/u}"; v="${v//ü/u}"
  v="${v//ç/c}"; v="${v//ñ/n}"
  v="${v//À/A}"; v="${v//Â/A}"; v="${v//Ä/A}"; v="${v//Á/A}"; v="${v//Ã/A}"
  v="${v//É/E}"; v="${v//È/E}"; v="${v//Ê/E}"; v="${v//Ë/E}"
  v="${v//Î/I}"; v="${v//Ï/I}"; v="${v//Ô/O}"; v="${v//Ö/O}"
  v="${v//Û/U}"; v="${v//Ü/U}"; v="${v//Ç/C}"; v="${v//Ñ/N}"
  printf '%s' "$v"
}

# Le préfixe de la marque, calculé une fois.
calculer_prefixe() {
  local propre mots
  propre="$(sans_accents "$1" | tr -c 'A-Za-z0-9 ' ' ' | tr -s ' ')"
  mots=$(printf '%s' "$propre" | wc -w)

  if [ "$mots" -ge 2 ]; then
    # Les initiales, trois au maximum : au-delà, la référence cesse d'être
    # lisible et personne ne la recopie juste.
    printf '%s' "$propre" \
      | awk '{ for (i = 1; i <= NF && i <= 3; i++) printf "%s", toupper(substr($i, 1, 1)) }'
  else
    printf '%s' "$propre" | tr '[:lower:]' '[:upper:]' | cut -c1-3
  fi
}

if [ -n "$PREFIXE_IMPOSE" ]; then
  PREFIXE="$(printf '%s' "$PREFIXE_IMPOSE" | tr -cd 'A-Za-z0-9' | tr '[:lower:]' '[:upper:]')"
else
  PREFIXE="$(calculer_prefixe "$NOM")"
fi

if [ -z "$PREFIXE" ]; then
  echo "  Impossible de tirer un préfixe du nom « $NOM »"
  echo "  Donnez-en un en quatrième argument, par exemple SDTM."
  exit 1
fi

# Les références déjà attribuées dans ce catalogue, pour départager les
# doublons. Deux produits d'une même gamme au même format se ressemblent
# beaucoup, et c'est précisément le cas où une collision est probable.
REFS_UTILISEES=" "

# Le résultat sort par cette variable, et NON par `printf` récupéré en
# substitution de commande. Une substitution `$(...)` s'exécute dans un
# sous-shell : la liste des références déjà attribuées y était bien mise à
# jour, puis perdue au retour. La détection de doublon ne voyait donc jamais
# rien, et « Thé citron » et « Thé menthe » produisaient la même référence,
# ce que la contrainte d'unicité de `produits` a heureusement rattrapé.
REF_GENEREE=""

deja_pris() {
  [ "${REFS_UTILISEES#* $1 }" != "$REFS_UTILISEES" ]
}

generer_reference() {
  local propre mots lettres qualifiant chiffres candidat n
  propre="$(sans_accents "$1" | tr -c 'A-Za-z0-9 ' ' ' | tr -s ' ')"

  lettres="$(printf '%s' "$propre" | awk '{ print toupper(substr($1, 1, 3)) }')"
  [ -z "$lettres" ] && lettres="PRD"

  # Au plus QUATRE chiffres. Trois suffisaient pour 400g ou 900g, mais
  # tronquaient « 4500g » en 450 : la référence affichait alors un format qui
  # n'existe pas, ce qui est pire qu'une référence sans chiffre du tout. Aucun
  # conditionnement courant ne dépasse quatre chiffres.
  chiffres="$(printf '%s' "$propre" | tr -cd '0-9' | cut -c1-4)"

  candidat="$PREFIXE-$lettres$chiffres"

  # EN CAS DE COLLISION, ON QUALIFIE AVANT DE NUMÉROTER.
  #
  # Un fabricant de riz a forcément plusieurs riz de 900 g. Un suffixe
  # incrémental donnerait RIZ900, RIZ9002, RIZ9003 : unique, et strictement
  # inutilisable sur un bon de livraison, puisque rien ne dit lequel est le
  # basmati. On insère donc deux lettres du mot SUIVANT, qui est justement
  # celui qui distingue les variantes : RIZ900, RIZBA900, RIZPA900.
  #
  # Le numéro ne reste qu'en dernier recours, quand même le qualifiant ne
  # suffit pas à départager.
  if deja_pris "$candidat"; then
    # ON ESSAIE CHAQUE MOT SUIVANT, pas seulement le premier.
    #
    # S'arrêter au premier mot significatif donnait SAVLI400 pour « Savon
    # liquide main Madar Marseille » : unique, mais « LI » de « liquide » est
    # justement le mot que ce produit PARTAGE avec celui qu'il doit distinguer.
    # En parcourant les mots dans l'ordre, on s'arrête au premier qui libère
    # réellement la référence, c'est-à-dire au premier qui diffère : ici
    # « Marseille », d'où SAVMA400.
    #
    # Les mots-outils sont écartés d'emblée : « Détergent EN poudre » donnait
    # DETEN, qui ne dit rien de rien.
    for qualifiant in $(printf '%s' "$propre" | awk '
      BEGIN {
        split("de du des la le les un une en a au aux et avec pour sans par sur", v, " ")
        for (i in v) vide[v[i]] = 1
      }
      {
        for (i = 2; i <= NF; i++) {
          m = tolower($i)
          if ($i ~ /^[A-Za-z]/ && !(m in vide) && length($i) >= 2) print toupper(substr($i, 1, 2))
        }
      }'); do
      if ! deja_pris "$PREFIXE-$lettres$qualifiant$chiffres"; then
        candidat="$PREFIXE-$lettres$qualifiant$chiffres"
        break
      fi
    done

    # Dernier recours seulement : quand aucun mot du nom ne suffit à départager.
    if deja_pris "$candidat"; then
      n=2
      while deja_pris "$candidat$n"; do
        n=$((n + 1))
      done
      candidat="$candidat$n"
    fi
  fi

  REFS_UTILISEES="$REFS_UTILISEES$candidat "
  REF_GENEREE="$candidat"
}

# Le CSV devient une série de VALUES. On ignore l'en-tête et les lignes vides,
# et on tolère un CRLF, que produisent tous les tableurs sous Windows.
VALEURS=""
LIGNE_NUM=0
IGNOREES=0
GENEREES=0
while IFS= read -r ligne || [ -n "$ligne" ]; do
  LIGNE_NUM=$((LIGNE_NUM + 1))
  ligne="${ligne%$'\r'}"
  [ "$LIGNE_NUM" = "1" ] && continue      # en-tête
  [ -z "${ligne// /}" ] && continue        # ligne vide

  IFS=';' read -r p_nom p_ref p_cat <<< "$ligne"
  p_nom="$(printf '%s' "$p_nom" | sed 's/^ *//; s/ *$//')"
  p_ref="$(printf '%s' "$p_ref" | sed 's/^ *//; s/ *$//')"
  p_cat="$(printf '%s' "$p_cat" | sed 's/^ *//; s/ *$//')"

  if [ -z "$p_nom" ]; then
    echo "  ligne $LIGNE_NUM ignorée : nom de produit manquant"
    IGNOREES=$((IGNOREES + 1))
    continue
  fi

  if [ -z "$p_ref" ]; then
    generer_reference "$p_nom"
    p_ref="$REF_GENEREE"
    GENEREES=$((GENEREES + 1))
  else
    # Une référence fournie est réservée elle aussi, sinon une référence
    # générée plus bas pourrait tomber dessus.
    REFS_UTILISEES="$REFS_UTILISEES$p_ref "
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
psql -w -v ON_ERROR_STOP=1 "$CONNEXION" <<SQL
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
if [ "$GENEREES" != "0" ]; then
  echo "$GENEREES référence(s) générée(s) sur le préfixe « $PREFIXE »."
  echo "Elles servent au distributeur à retrouver un produit sur un bon de"
  echo "livraison. Si le fabricant fournit plus tard sa vraie nomenclature,"
  echo "un UPDATE sur produits.reference suffit, rien n'en dépend ailleurs."
fi
if [ "$IGNOREES" != "0" ]; then
  echo "$IGNOREES ligne(s) du CSV ignorée(s), voir ci-dessus."
fi
echo
echo "ÉTAPE SUIVANTE, sans laquelle le routage ne marche pas : chaque"
echo "distributeur doit revendiquer ses boutiques pour cette marque, depuis"
echo "l'onglet Réseau de l'application. Une boutique non revendiquée produit"
echo "des ruptures sans destinataire, invisibles pendant deux heures."
echo
