#!/usr/bin/env bash
# Ouvre le compte de connexion d'un fabricant déjà enregistré.
#
#   bash scripts/ouvrir-compte-fabricant.sh              # tous ceux qui n'en ont pas
#   bash scripts/ouvrir-compte-fabricant.sh "SDTM-CI"    # un seul, par son nom
#
# POURQUOI CE SCRIPT EXISTE. `creer-fabricant.sh` crée la marque et son
# catalogue, mais pas de compte de connexion, et c'était juste au moment où il
# a été écrit : le fabricant n'avait aucun écran, un compte l'aurait laissé
# devant une page vide. Son propre en-tête annonçait la suite, « le rattacher
# plus tard, quand son tableau de bord existera, se fera par
# `rattacher_compte_auth()` ». Le tableau de bord existe. C'est cette suite.
#
# CE QU'IL FAUT AVOIR EN TÊTE : sans lui, un fabricant recruté en direct ne peut
# pas se connecter du tout. Rien ne le signale, puisque sa marque, son catalogue
# et ses ruptures existent parfaitement en base. Le défaut ne se voit qu'en
# essayant de se connecter, c'est-à-dire devant le client.
#
# Le mot de passe s'affiche UNE FOIS et n'est stocké nulle part. Il se remet en
# main propre ou se dicte au téléphone, comme pour tous les comptes du réseau.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FILTRE="${1:-}"
ENV_FICHIER="${YALLA_ENV:-$HOME/Downloads/jarvis-starter-kit/.env}"

lire() {
  grep -E "^$1=" "$ENV_FICHIER" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'"' \r'
}

URL="$(lire SUPABASE_URL)"
CLE_SERVICE="$(lire SUPABASE_SERVICE_ROLE_KEY)"
MDP_BASE="$(lire SUPABASE_DB_PASSWORD)"
REF="$(printf '%s' "$URL" | sed 's|https://||; s|\.supabase\.co.*||')"

[ -n "$URL" ]         || { echo "  SUPABASE_URL absente de $ENV_FICHIER"; exit 1; }
[ -n "$CLE_SERVICE" ] || { echo "  SUPABASE_SERVICE_ROLE_KEY absente de $ENV_FICHIER"; exit 1; }
[ -n "$MDP_BASE" ]    || { echo "  SUPABASE_DB_PASSWORD absente de $ENV_FICHIER"; exit 1; }
command -v psql >/dev/null 2>&1 || { echo "  psql introuvable dans le PATH"; exit 1; }

export PGPASSWORD="$MDP_BASE"
CONNEXION="postgresql://postgres.$REF@aws-1-eu-west-3.pooler.supabase.com:5432/postgres"

# TOUT EN MAJUSCULES, ET C'EST LE POINT ESSENTIEL. Ce mot de passe se dicte au
# téléphone ou sur le pas d'une porte. Or une majuscule et une minuscule de la
# même lettre se prononcent exactement pareil : dicter « d » sans préciser la
# casse fait taper l'une pour l'autre une fois sur deux, et la connexion est
# refusée sans que personne ne comprenne pourquoi. C'est arrivé sur le compte de
# l'agent recenseur, qui n'a pas pu se connecter le jour du premier test.
#
# Ni I ni O ni 0 ni 1 non plus, qui se confondent à la lecture. L'alphabet est le
# même ici, dans les autres scripts, dans la page d'administration et dans
# l'application : cinq implémentations qui doivent rendre la même forme.
#
# La lecture passe par une substitution de processus plutôt que par un tube :
# sous `pipefail`, `tr … | head -c 8` ferme le tube et fait échouer `tr` sur un
# SIGPIPE, ce qui tuait le script sans message.
motdepasse() {
  LC_ALL=C tr -dc 'ABCDEFGHJKMNPQRSTUVWXYZ23456789' \
    < <(head -c 256 /dev/urandom) | cut -c1-8
}

echo
echo "Comptes de connexion des fabricants, sur $REF"
echo

CLAUSE="WHERE u.auth_user_id IS NULL"
if [ -n "$FILTRE" ]; then
  CLAUSE="$CLAUSE AND f.nom ILIKE '%$(printf '%s' "$FILTRE" | sed "s/'/''/g")%'"
fi

# `tr -d '\r'` n'est pas une précaution de style. Sous Windows, psql termine
# ses lignes par CRLF, et le retour chariot reste collé à la dernière valeur de
# chaque ligne. Il devient alors un caractère de commande dans le corps JSON
# envoyé à l'API, qui répond « invalid character '\r' in string ». Le message
# ne dit évidemment pas d'où vient le retour chariot.
SANS_COMPTE="$(psql -w -tA -F'|' -c "
  SELECT f.nom, u.telephone
    FROM fabricants f JOIN utilisateurs u ON u.id = f.utilisateur_id
   $CLAUSE
   ORDER BY f.nom" "$CONNEXION" | tr -d '\r')"

if [ -z "$SANS_COMPTE" ]; then
  echo "  Rien à faire : chaque fabricant visé a déjà son compte."
  echo
  exit 0
fi

ECHECS=0
while IFS='|' read -r nom tel; do
  [ -n "$tel" ] || continue
  mdp="$(motdepasse)"

  reponse="$(curl -s -X POST "$URL/auth/v1/admin/users" \
    -H "apikey: $CLE_SERVICE" \
    -H "Authorization: Bearer $CLE_SERVICE" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${tel}@yalla.ci\",\"password\":\"$mdp\",\"email_confirm\":true}")"

  auth_id="$(printf '%s' "$reponse" | sed -n 's/.*"id":"\([0-9a-f-]\{36\}\)".*/\1/p' | head -1)"
  if [ -z "$auth_id" ]; then
    printf '  ✗ %-26s %s\n' "$nom" "$(printf '%s' "$reponse" | head -c 140)"
    ECHECS=$((ECHECS + 1))
    continue
  fi

  # `rattacher_compte_auth` n'écrit que sur une ligne dont `auth_user_id` est
  # encore nul : elle ne peut donc pas détourner un compte existant. Si elle ne
  # rattache rien, on supprime le compte de connexion qu'on vient de créer,
  # plutôt que de laisser un compte orphelin capable de se connecter dans le
  # vide.
  rattache="$(psql -w -tAc \
    "SELECT rattacher_compte_auth('$tel', '$auth_id') IS NOT NULL" "$CONNEXION" \
    | tr -d '\r')"

  if [ "$rattache" != "t" ]; then
    curl -s -o /dev/null -X DELETE "$URL/auth/v1/admin/users/$auth_id" \
      -H "apikey: $CLE_SERVICE" -H "Authorization: Bearer $CLE_SERVICE"
    printf '  ✗ %-26s rattachement refusé, compte annulé\n' "$nom"
    ECHECS=$((ECHECS + 1))
    continue
  fi

  printf '  ✓ %-26s %s / %s\n' "$nom" "$tel" "$mdp"
done <<< "$SANS_COMPTE"

echo
if [ "$ECHECS" != "0" ]; then
  echo "  $ECHECS échec(s)."
  exit 1
fi
echo "  Notez ces mots de passe MAINTENANT : ils ne sont stockés nulle part et"
echo "  ne seront plus jamais affichés. Ils se remettent en main propre."
echo
echo "  Connexion : https://yalla.ci/rejoindre.html"
echo
