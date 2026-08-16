# Yalla

Plateforme de distribution de proximité pour la Côte d'Ivoire — **géolocalisation
temps réel**, **signalement de ruptures de stock** et **caisse enregistreuse**,
réunis dans une seule application mobile iOS + Android. Lancement prévu à Abidjan.

> Les boutiques signalent un produit manquant en un geste. La rupture apparaît
> instantanément sur la carte du fabricant concerné et des livreurs à proximité.

---

## Démarrage rapide

```bash
npm run setup
```

Puis, selon ce sur quoi vous travaillez :

```bash
npm run dev:backend    # API      → http://localhost:3000
npm run dev:landing    # Vitrine  → http://localhost:4173
```

L'API a besoin d'une base PostgreSQL + PostGIS. Voir [Base de données](#base-de-données).

### Prérequis

| Outil | Version | Nécessaire pour |
|---|---|---|
| Node.js | ≥ 18 | backend, landing |
| PostgreSQL | ≥ 14, avec PostGIS | backend |
| Flutter SDK | ≥ 3.16 | mobile uniquement |

Node seul suffit pour travailler sur le backend ou la landing page.

---

## Structure

| Dossier | Contenu |
|---|---|
| [`backend/`](backend/) | API NestJS — REST + WebSocket, 9 modules, JWT par rôle |
| [`database/`](database/) | 10 migrations SQL + seed de développement |
| [`mobile/`](mobile/) | Application Flutter (authentification + un écran par rôle) |
| [`landing/`](landing/) | Site vitrine public, HTML/CSS/JS sans framework |
| [`maquettes/`](maquettes/) | 5 prototypes HTML cliquables, un par interface |
| [`docs/`](docs/) | Cahier des charges, modèle de données, stack technique, historique |
| [`scripts/`](scripts/) | Setup, lint, test |

Ce dépôt regroupe des livrables auparavant numérotés. Correspondance :

| Avant | Maintenant |
|---|---|
| `01_cahier_des_charges/` | `docs/01_cahier_des_charges/` |
| `02_modele_de_donnees/` | `docs/02_modele_de_donnees/` |
| `03_stack_technique/` | `docs/03_stack_technique/` |
| `04_maquettes/` | `maquettes/` |
| `05_base_de_donnees/database/` | `database/` |
| `06_backend_api/` | `backend/` |
| `07_mobile/` | `mobile/` |
| `README.md` (racine) | `docs/HISTORIQUE.md` |

La landing page est le seul ajout : elle n'existait pas dans les livrables initiaux.

---

## Les cinq rôles

| Rôle | Ce qu'il fait |
|---|---|
| **Point de vente** | Signale ses ruptures, encaisse ses ventes, reçoit notifications et sondages |
| **Fabricant** | Suit son réseau attribué, reçoit les ruptures de son seul catalogue, pilote ses livreurs |
| **Livreur** | Voit les ruptures à proximité, prend la course, contacte la boutique, livre |
| **Agent recenseur** | Enregistre et met à jour les points de vente sur le terrain |
| **Administrateur** | Supervise l'ensemble du réseau, diffuse notifications et sondages, extrait les statistiques |

Chaque rôle a un périmètre de données strict — détaillé dans
[`AGENTS.md`](AGENTS.md) §6 et dans le cahier des charges.

---

## Base de données

Les migrations SQL sont la **source de vérité du schéma**. TypeORM tourne avec
`synchronize: false` et ne doit jamais le régénérer : le schéma contient des
colonnes PostGIS, des vues, et un trigger qui crée automatiquement une rupture
lorsqu'une vente vide un stock.

```bash
createdb yalla
psql -d yalla -c "CREATE EXTENSION IF NOT EXISTS postgis;"
for f in database/migrations/*.sql; do psql -d yalla -f "$f"; done
psql -d yalla -f database/seed/seed_dev.sql   # jeu de données de dev
```

---

## Configuration

```bash
cp backend/.env.example backend/.env
```

Renseignez la connexion PostgreSQL et un `JWT_SECRET`. Aucun secret ne doit être
committé.

Pour le mobile, l'URL de l'API se passe à la compilation :

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

---

## Stack

Flutter (mobile) · NestJS + TypeScript (API) · PostgreSQL + PostGIS (données) ·
Socket.io (temps réel) · Firebase Cloud Messaging (push) · Google Maps SDK
(cartographie) · CinetPay (paiement mobile) · NindoHost (hébergement).

Les arbitrages et leurs alternatives sont justifiés dans
[`docs/03_stack_technique/`](docs/03_stack_technique/).

---

## État du projet

Ce dépôt est un socle de développement, pas un produit en production.

**Vérifié** (2026-08-16) : les dépendances backend s'installent, le TypeScript
compile sans erreur, `nest build` produit son `dist/`, et la landing page est
servie correctement.

**Non vérifié** : le backend n'a jamais tourné contre une vraie base, les
migrations SQL n'ont jamais été appliquées, et le mobile n'a jamais été compilé
(SDK Flutter absent). Attendez-vous à des erreurs au premier démarrage réel.

Par ailleurs :

- **aucun test automatisé** n'existe à ce jour ;
- chaque interface mobile se limite à un écran d'accueil ;
- push FCM, paiement CinetPay et export Excel/PDF sont **déclarés mais non branchés** ;
- rien n'est déployé.

L'historique complet des décisions est dans [`docs/HISTORIQUE.md`](docs/HISTORIQUE.md).

---

## Travailler avec un agent de code

[`AGENTS.md`](AGENTS.md) contient les instructions destinées aux agents
automatisés : conventions, contraintes de schéma, périmètres par rôle et pièges
connus. Voir aussi [`docs/DEVIN.md`](docs/DEVIN.md) pour la configuration Devin.
