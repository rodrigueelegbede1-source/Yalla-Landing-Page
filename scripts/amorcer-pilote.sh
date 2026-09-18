#!/usr/bin/env bash
# Crée les tout premiers comptes Yalla, ceux que l'application ne peut pas créer
# elle-même.
#
#   bash scripts/amorcer-pilote.sh
#
# LE PROBLÈME QU'IL RÉSOUT. Depuis la migration `gestion_reseau`, les comptes se
# créent dans l'application : l'agent recenseur inscrit les boutiques, le
# distributeur enrôle ses livreurs. Mais il faut déjà un compte pour se
# connecter, et personne ne peut créer le premier. C'est le seul endroit où la
# ligne de commande reste nécessaire, et il est volontairement réduit à deux
# comptes : un administrateur et un agent recenseur.
#
# Tout le reste du réseau se crée ensuite depuis le téléphone.
#
# VARIABLES ATTENDUES, lues dans le `.env` de l'espace de travail :
#   SUPABASE_URL, SUPABASE_DB_PASSWORD, SUPABASE_SERVICE_ROLE_KEY
#
# La clé de service contourne RLS. Elle ne sort jamais de ce script, n'entre
# jamais dans l'application, et ne doit jamais être commitée.
set -euo pipefail

ENV_FICHIER="${YALLA_ENV:-$HOME/Downloads/jarvis-starter-kit/.env}"

lire() {
  grep -E "^$1=" "$ENV_FICHIER" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'"' \r'
}

URL="$(lire SUPABASE_URL)"
CLE_SERVICE="$(lire SUPABASE_SERVICE_ROLE_KEY)"
MDP_BASE="$(lire SUPABASE_DB_PASSWORD)"
REF="$(basename "${URL%%.supabase.co}" | sed 's|https://||')"

[ -n "$URL" ]         || { echo "SUPABASE_URL absente de $ENV_FICHIER"; exit 1; }
[ -n "$CLE_SERVICE" ] || { echo "SUPABASE_SERVICE_ROLE_KEY absente de $ENV_FICHIER"; exit 1; }
[ -n "$MDP_BASE" ]    || { echo "SUPABASE_DB_PASSWORD absente de $ENV_FICHIER"; exit 1; }

CONNEXION="postgresql://postgres.$REF@aws-1-eu-west-3.pooler.supabase.com:5432/postgres"
export PGPASSWORD="$MDP_BASE"

# Mot de passe lisible à voix haute : ni l/1 ni O/0, qui se confondent quand on
# dicte un identifiant à quelqu'un qui le note sur un carnet.
#
# L'entrée est bornée à 256 octets au lieu d'être coupée par `head`. Avec
# `/dev/urandom | tr | head -c 8`, `head` se ferme dès le huitième caractère,
# `tr` reçoit un SIGPIPE et sort en 141 ; sous `set -o pipefail`, l'affectation
# échoue et `set -e` interrompt le script juste après avoir produit la bonne
# valeur. Panne parfaitement silencieuse, et le script s'arrêtait là.
motdepasse() {
  LC_ALL=C tr -dc 'ABCDEFGHJKMNPQRSTUVWXYZ23456789' < <(head -c 256 /dev/urandom) | cut -c1-8
}

# Même normalisation que `normaliser_telephone()` en SQL, `normaliserTelephone`
# en Dart et son homologue dans la fonction Edge. Les quatre doivent coïncider.
#
# Écrit en `if` et non en `&&` : sous `set -e`, une liste `test && affectation`
# dont le test est faux rend un code non nul et interrompt le script. Le premier
# jet mourait ainsi en silence, sur un numéro parfaitement valide.
normaliser() {
  local v="${1//[^0-9]/}"
  if [ "${v:0:5}" = "00225" ]; then
    v="${v:2}"
  fi
  # Dix chiffres = numéro national, quel que soit le premier chiffre : les
  # mobiles commencent par 01, 05 ou 07, les fixes par 25 ou 27.
  if [ "${#v}" = "10" ]; then
    v="225$v"
  fi
  printf '%s' "$v"
}

# Crée un compte complet : connexion, ligne `utilisateurs`, ligne du rôle.
#
#   creer_compte "Nom" "telephone" "role" "colonnes" "valeurs"
#
# Les deux derniers arguments décrivent la ligne du rôle, qui diffère d'une
# table à l'autre. Laissés vides pour un administrateur, qui n'en a pas.
creer_compte() {
  local nom="$1" tel_brut="$2" role="$3" table="${4:-}" colonnes="${5:-}" valeurs="${6:-}"
  local tel mdp email reponse auth_id

  tel="$(normaliser "$tel_brut")"
  if [ "${#tel}" != 13 ]; then
    echo "  ✗ numéro invalide : $tel_brut"
    return 1
  fi

  mdp="$(motdepasse)"
  email="${tel}@yalla.ci"

  reponse="$(curl -s -X POST "$URL/auth/v1/admin/users" \
    -H "apikey: $CLE_SERVICE" \
    -H "Authorization: Bearer $CLE_SERVICE" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$mdp\",\"email_confirm\":true}")"

  auth_id="$(printf '%s' "$reponse" | sed -n 's/.*"id":"\([0-9a-f-]\{36\}\)".*/\1/p' | head -1)"
  if [ -z "$auth_id" ]; then
    echo "  ✗ $nom : $(printf '%s' "$reponse" | head -c 200)"
    return 1
  fi

  # La ligne métier, dans la même transaction que le rattachement : un compte de
  # connexion sans rôle se connecte et n'a accès à rien.
  local ligne_role=""
  if [ -n "$table" ]; then
    ligne_role="INSERT INTO $table ($colonnes) VALUES ($valeurs);"
  fi

  psql "$CONNEXION" -w -v ON_ERROR_STOP=1 -q <<SQL
BEGIN;
INSERT INTO utilisateurs (nom, telephone, role, auth_user_id)
VALUES ('$(printf '%s' "$nom" | sed "s/'/''/g")', '$tel', '$role', '$auth_id');
$ligne_role
COMMIT;
SQL

  printf '  ✓ %-22s %s / %s\n' "$nom" "$tel" "$mdp"
}

echo
echo "Amorçage du pilote Yalla sur $REF"
echo

if [ "$(psql "$CONNEXION" -w -tAc 'SELECT count(*) FROM utilisateurs')" != "0" ]; then
  echo "  La base contient déjà des comptes. Ce script ne s'exécute que sur une"
  echo "  base vide, pour éviter de créer des doublons."
  echo "  Pour repartir de zéro : psql \"\$CONNEXION\" -f supabase/purge-demonstration.sql"
  exit 1
fi

echo "Comptes créés. NOTEZ CES MOTS DE PASSE, ils ne sont stockés nulle part."
echo

creer_compte "Elegson Admin" "${YALLA_TEL_ADMIN:-0707000001}" "administrateur"

creer_compte "Agent recenseur" "${YALLA_TEL_AGENT:-0707000002}" "agent_recenseur" \
  "agents_recenseurs" \
  "utilisateur_id, secteur" \
  "(SELECT id FROM utilisateurs WHERE telephone = '$(normaliser "${YALLA_TEL_AGENT:-0707000002}")'), 'Abidjan'"

echo
echo "L'agent recenseur peut maintenant inscrire les boutiques depuis"
echo "l'application. Les distributeurs et les livreurs suivent, sans SQL."
echo
