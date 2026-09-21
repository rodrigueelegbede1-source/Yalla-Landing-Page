#!/usr/bin/env bash
# Réattribue un mot de passe à un compte du réseau.
#
#   bash scripts/reinitialiser-mot-de-passe.sh              # liste les comptes
#   bash scripts/reinitialiser-mot-de-passe.sh 0745000000   # un compte
#   bash scripts/reinitialiser-mot-de-passe.sh --tous       # tous
#
# POURQUOI CE SCRIPT EXISTE. Aucun mot de passe n'est stocké en clair, nulle
# part, et c'est voulu : ils sont affichés une fois à la création puis remis en
# main propre. La contrepartie est qu'un mot de passe perdu est perdu pour de
# bon, et que le compte devient inutilisable sans moyen de le rattraper.
#
# Le guide de terrain renvoyait jusqu'ici vers le tableau de bord Supabase,
# Authentication puis Users. Cela marche, mais il faut retrouver quel compte
# correspond à quel rôle parmi des adresses techniques du genre
# `2250745000000@yalla.ci`, et la manipulation est fastidieuse à six comptes.
#
# CE QUE LE SCRIPT NE FAIT PAS : il ne touche à aucune donnée métier. Il change
# le mot de passe d'un compte de connexion existant, rien d'autre. Le compte, la
# boutique, les stocks, l'historique restent intacts.
#
# LE NOUVEAU MOT DE PASSE S'AFFICHE UNE FOIS, et n'est écrit dans aucun fichier.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CIBLE="${1:-}"
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

# Même normalisation qu'en SQL, en Dart et dans la fonction Edge. Dix chiffres
# valent un numéro national, quel que soit le premier : les mobiles ivoiriens
# commencent par 01, 05 ou 07, les fixes par 25 ou 27.
normaliser() {
  local v="${1//[^0-9]/}"
  if [ "${v:0:5}" = "00225" ]; then v="${v:2}"; fi
  if [ "${#v}" = "10" ]; then v="225$v"; fi
  printf '%s' "$v"
}

# Sans l, sans 1, sans O, sans 0 : ce mot de passe se dicte au téléphone.
motdepasse() {
  LC_ALL=C tr -dc 'ABCDEFGHJKMNPQRTUVWXYabcdefghijkmnpqrstuvwxy23456789' \
    < <(head -c 256 /dev/urandom) | cut -c1-10
}

# `tr -d '\r'` : sous Windows psql termine ses lignes par CRLF, et le retour
# chariot resterait collé à la dernière valeur de chaque ligne, où il devient
# un caractère de commande dans le corps JSON envoyé à l'API.
COMPTES="$(psql -w -tA -F'|' -c "
  SELECT u.telephone, u.role::TEXT, u.nom, u.auth_user_id::TEXT,
         COALESCE(p.nom, d.nom, f.nom, '')
    FROM utilisateurs u
    LEFT JOIN points_de_vente p ON p.utilisateur_id = u.id
    LEFT JOIN distributeurs d   ON d.utilisateur_id = u.id
    LEFT JOIN fabricants f      ON f.utilisateur_id = u.id
   WHERE u.auth_user_id IS NOT NULL
   ORDER BY u.role, u.nom" "$CONNEXION" | tr -d '\r')"

if [ -z "$COMPTES" ]; then
  echo "  Aucun compte de connexion sur ce projet."
  exit 1
fi

if [ -z "$CIBLE" ]; then
  echo
  echo "Comptes de connexion du réseau"
  echo
  printf '  %-16s %-18s %s\n' "IDENTIFIANT" "RÔLE" "QUI"
  while IFS='|' read -r tel role nom auth_id metier; do
    [ -n "$tel" ] || continue
    printf '  %-16s %-18s %s\n' "${tel#225}" "$role" "$nom${metier:+ · $metier}"
  done <<< "$COMPTES"
  echo
  echo "  Pour en réattribuer un :"
  echo "    bash scripts/reinitialiser-mot-de-passe.sh 0745000000"
  echo "  Pour tous :"
  echo "    bash scripts/reinitialiser-mot-de-passe.sh --tous"
  echo
  exit 0
fi

# Un seul compte, ou tous. Rien entre les deux : une expression approximative
# qui attraperait trois comptes au lieu d'un couperait l'accès de deux personnes
# sans que rien ne le dise.
if [ "$CIBLE" = "--tous" ]; then
  SELECTION="$COMPTES"
  echo
  echo "  Vous allez réattribuer le mot de passe de TOUS les comptes."
  echo "  Les anciens cesseront immédiatement de fonctionner."
  printf '  Tapez « oui » pour continuer : '
  read -r reponse
  if [ "$reponse" != "oui" ]; then echo "  Abandon."; exit 0; fi
else
  TEL="$(normaliser "$CIBLE")"
  SELECTION="$(printf '%s\n' "$COMPTES" | grep "^$TEL|" || true)"
  if [ -z "$SELECTION" ]; then
    echo "  Aucun compte pour le numéro « $CIBLE »."
    echo "  Lancez le script sans argument pour voir la liste."
    exit 1
  fi
fi

echo
ECHECS=0
while IFS='|' read -r tel role nom auth_id metier; do
  [ -n "$tel" ] || continue

  mdp="$(motdepasse)"

  code="$(curl -s -o /dev/null -w '%{http_code}' \
    -X PUT "$URL/auth/v1/admin/users/$auth_id" \
    -H "apikey: $CLE_SERVICE" \
    -H "Authorization: Bearer $CLE_SERVICE" \
    -H "Content-Type: application/json" \
    -d "{\"password\":\"$mdp\"}")"

  if [ "$code" != "200" ]; then
    printf '  ✗ %-22s HTTP %s\n' "$nom" "$code"
    ECHECS=$((ECHECS + 1))
    continue
  fi

  printf '  ✓ %-22s %-16s %-14s %s\n' "$role" "${tel#225}" "$mdp" "$nom${metier:+ · $metier}"
done <<< "$SELECTION"

echo
if [ "$ECHECS" != "0" ]; then
  echo "  $ECHECS échec(s)."
  exit 1
fi
echo "  Notez ces mots de passe MAINTENANT. Ils ne sont stockés nulle part et"
echo "  ne seront plus jamais affichés."
echo
echo "  Boutique, livreur et agent se connectent dans l'application."
echo "  Fabricant, distributeur et administrateur sur https://yalla.ci"
echo
