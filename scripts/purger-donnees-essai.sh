#!/usr/bin/env bash
# Remet les compteurs à zéro sans défaire le réseau.
#
#   bash scripts/purger-donnees-essai.sh --verifier   # ce qui serait supprimé
#   bash scripts/purger-donnees-essai.sh --purger     # supprime, après sauvegarde
#
# POURQUOI DISTINGUER LE RÉSEAU DES MOUVEMENTS. Un essai laisse deux natures de
# traces, et elles n'ont pas la même valeur :
#
#   * LE RÉSEAU : boutiques recensées, distributeurs, livreurs, marques,
#     catalogues, attributions, stocks. Il a coûté du terrain. On n'y touche
#     pas, jamais, et surtout pas pour « repartir propre ».
#
#   * LES MOUVEMENTS : ventes, ruptures, livraisons, transactions. Ils
#     appartiennent à l'essai, pas au pilote, et ils faussent tout ce qui se
#     calcule dessus. Trois ruptures périmées d'une journée de test suffisent
#     à afficher un taux de service de 25 % pendant des semaines, sur l'écran
#     même qui sert à décider si le produit marche.
#
# CE SCRIPT NE SUPPRIME QUE LA SECONDE NATURE.
#
# LA SAUVEGARDE N'EST PAS OPTIONNELLE. Elle part dans `livrable/` avant la
# première suppression, au format SQL rejouable. Une purge sans sauvegarde
# serait une perte sèche de la seule trace qu'un parcours complet a réellement
# fonctionné en production, ce qui est la preuve la plus précieuse du dépôt.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="${1:---verifier}"
ENV_FICHIER="${YALLA_ENV:-$HOME/Downloads/jarvis-starter-kit/.env}"
DOSSIER_SAUVEGARDE="${YALLA_LIVRABLE:-$HOME/Downloads/jarvis-starter-kit/livrable/Application}"

lire() {
  grep -E "^$1=" "$ENV_FICHIER" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'"' \r'
}

URL="$(lire SUPABASE_URL)"
MDP_BASE="$(lire SUPABASE_DB_PASSWORD)"
REF="$(printf '%s' "$URL" | sed 's|https://||; s|\.supabase\.co.*||')"

[ -n "$URL" ]      || { echo "  SUPABASE_URL absente de $ENV_FICHIER"; exit 1; }
[ -n "$MDP_BASE" ] || { echo "  SUPABASE_DB_PASSWORD absente de $ENV_FICHIER"; exit 1; }
command -v psql >/dev/null 2>&1 || { echo "  psql introuvable dans le PATH"; exit 1; }

export PGPASSWORD="$MDP_BASE"
CONNEXION="postgresql://postgres.$REF@aws-1-eu-west-3.pooler.supabase.com:5432/postgres"

say() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
ok()  { printf '  \033[32m✓ %s\033[0m\n' "$1"; }

# ── L'inventaire, dans les deux modes ───────────────────────────────────────

say "Ce que l'essai a laissé"
psql -w -c "
  SELECT 'ventes' AS mouvement, count(*) FROM ventes
  UNION ALL SELECT 'lignes de vente', count(*) FROM lignes_vente
  UNION ALL SELECT 'ruptures', count(*) FROM ruptures
  UNION ALL SELECT 'livraisons', count(*) FROM livraisons
  UNION ALL SELECT 'transactions', count(*) FROM transactions
  UNION ALL SELECT 'notifications', count(*) FROM notifications
  ORDER BY 1" "$CONNEXION"

say "Ce qui ne sera PAS touché"
psql -w -c "
  SELECT 'boutiques' AS reseau, count(*) FROM points_de_vente
  UNION ALL SELECT 'distributeurs', count(*) FROM distributeurs
  UNION ALL SELECT 'livreurs', count(*) FROM livreurs
  UNION ALL SELECT 'marques', count(*) FROM fabricants
  UNION ALL SELECT 'produits', count(*) FROM produits
  UNION ALL SELECT 'attributions', count(*) FROM attributions_reseau
  UNION ALL SELECT 'lignes de stock', count(*) FROM stocks
  UNION ALL SELECT 'comptes', count(*) FROM utilisateurs
  ORDER BY 1" "$CONNEXION"

if [ "$MODE" != "--purger" ]; then
  echo
  echo "  Rien n'a été supprimé. Pour purger pour de bon :"
  echo "    bash scripts/purger-donnees-essai.sh --purger"
  echo
  exit 0
fi

# ── La sauvegarde, avant toute suppression ──────────────────────────────────

say "Sauvegarde"
mkdir -p "$DOSSIER_SAUVEGARDE"
FICHIER="$DOSSIER_SAUVEGARDE/$(date +%Y-%m-%d)_yalla_mouvements-avant-purge.sql"

# PG_DUMP REFUSE DE SAUVEGARDER UN SERVEUR PLUS RÉCENT QUE LUI, et il a raison :
# il ne connaît pas les objets apparus après sa propre version. Supabase tourne
# en 17.6 ; le pg_dump du PATH de cette machine est en 16.4, et l'appel échoue
# sur « annulation à cause de la différence des versions ».
#
# On cherche donc le pg_dump le plus récent disponible, plutôt que d'abandonner.
# Sans cette recherche, le script refusait de purger pour une raison qui n'avait
# rien à voir avec la purge, et le message ne le disait pas.
trouver_pg_dump() {
  local meilleur="" meilleure_version=0 candidat version
  for candidat in \
    "$(command -v pg_dump 2>/dev/null)" \
    /c/Program\ Files/PostgreSQL/*/bin/pg_dump.exe \
    /usr/lib/postgresql/*/bin/pg_dump \
    /opt/homebrew/opt/postgresql@*/bin/pg_dump
  do
    [ -n "$candidat" ] && [ -x "$candidat" ] || continue
    version="$("$candidat" --version 2>/dev/null | grep -oE '[0-9]+' | head -1)"
    [ -n "$version" ] || continue
    if [ "$version" -gt "$meilleure_version" ]; then
      meilleure_version="$version"
      meilleur="$candidat"
    fi
  done
  printf '%s' "$meilleur"
}

PG_DUMP="$(trouver_pg_dump)"
if [ -z "$PG_DUMP" ]; then
  echo "  ✗ pg_dump introuvable. Sans sauvegarde, on ne supprime rien."
  exit 1
fi
printf '  pg_dump retenu : %s\n' "$("$PG_DUMP" --version)"

# `--data-only` et la liste explicite des tables : on sauvegarde les
# mouvements, pas le schéma ni le réseau. Un fichier rejouable tel quel sur une
# base au même schéma.
if ! "$PG_DUMP" --data-only --no-owner --no-privileges \
     -t ventes -t lignes_vente -t ruptures -t livraisons -t transactions \
     -f "$FICHIER" "$CONNEXION" 2>"$FICHIER.err"; then
  sed 's/^/    /' "$FICHIER.err" | head -4
  rm -f "$FICHIER.err"
  echo "  ✗ la sauvegarde a échoué, rien n'a été supprimé"
  exit 1
fi
rm -f "$FICHIER.err"
ok "écrite dans $(basename "$FICHIER")"

TAILLE=$(wc -c < "$FICHIER" | tr -d ' ')
if [ "$TAILLE" -lt 100 ]; then
  echo "  ✗ sauvegarde suspecte ($TAILLE octets), rien n'a été supprimé"
  exit 1
fi

# ── La purge ────────────────────────────────────────────────────────────────

say "Purge"

# L'ORDRE COMPTE, et il descend des dépendances : une transaction pointe une
# livraison, une livraison pointe une rupture, une ligne de vente pointe une
# vente. Supprimer en tête de chaîne ferait échouer la transaction entière sur
# une violation de clé étrangère.
#
# Tout dans une seule transaction : une purge à moitié faite laisserait des
# livraisons orphelines, c'est-à-dire un état que le produit ne sait pas lire.
psql -w -v ON_ERROR_STOP=1 -q -c "
BEGIN;
DELETE FROM transactions;
DELETE FROM livraisons;
DELETE FROM sondage_reponses;
DELETE FROM ruptures;
DELETE FROM lignes_vente;
DELETE FROM ventes;
COMMIT;" "$CONNEXION" && ok "mouvements supprimés" \
  || { echo "  ✗ purge refusée, la base est inchangée"; exit 1; }

# Les lignes de stock ne sont pas supprimées, mais celles tombées à zéro sont
# relevées. Sans cela la purge ne servirait à rien : la rupture naît d'un stock
# à zéro, et la première vente enregistrée après la purge en recréerait
# aussitôt une identique sur la même référence.
#
# Douze cartons : de quoi encaisser plusieurs ventes avant que le mécanisme ne
# se redéclenche, ce qui est précisément ce qu'on veut observer sur le terrain.
say "Stocks"
psql -w -q -c "
  UPDATE stocks SET quantite = 12, date_maj = now() WHERE quantite <= 0" "$CONNEXION" \
  && ok "les références à zéro sont remontées à douze"

# Le SQL passé en argument reste en ASCII pur. Git Bash sous Windows transmet
# les arguments en cp1252, et le serveur les attend en UTF-8 : un simple accent
# dans une chaîne littérale fait échouer la requête sur « invalid byte sequence
# for encoding UTF8 ». Les accents vivent donc dans les fichiers, jamais dans un
# `psql -c`.
say "Etat obtenu"
psql -w -c "
  SELECT boutiques_actives, distributeurs, livreurs_actifs, produits,
         ruptures_ouvertes, COALESCE(taux_de_service_pct::TEXT, 'a calculer') AS taux
    FROM v_supervision_reseau" "$CONNEXION"

echo
echo "  Le réseau est intact, les compteurs repartent de zéro."
echo "  Sauvegarde : $FICHIER"
echo
