# AGENTS.md — instructions pour agents de code

Ce fichier est le point d'entrée pour tout agent automatisé (Devin, Claude Code,
Codex…) travaillant sur ce dépôt. Lis-le en entier avant de modifier quoi que ce soit.

---

## 1. Le projet en une minute

**Yalla** est une application mobile 3 en 1 pour la distribution de proximité en
Côte d'Ivoire (lancement Abidjan, iOS + Android) :

1. **Géolocalisation temps réel** des points de vente et des livreurs (modèle Uber).
2. **Signalement de ruptures de stock**, transmis en temps réel au fabricant concerné.
3. **Caisse enregistreuse** embarquée (modèle Loyverse).

Cinq rôles, cinq interfaces, des droits distincts :
`administrateur`, `fabricant`, `livreur`, `point_de_vente`, `agent_recenseur`.

Le cahier des charges fait foi : `docs/01_cahier_des_charges/`.

---

## 2. Carte du dépôt

| Dossier | Contenu | Techno |
|---|---|---|
| `backend/` | API REST + WebSocket, 9 modules | NestJS 10, TypeScript |
| `database/` | Migrations SQL numérotées + seed de dev | PostgreSQL 15 + PostGIS |
| `mobile/` | Squelette app (auth + 1 écran par rôle) | Flutter / Dart |
| `landing/` | Site vitrine public | HTML/CSS/JS sans framework |
| `maquettes/` | 5 prototypes HTML cliquables, un par rôle | HTML statique |
| `docs/` | Cahier des charges, modèle de données, stack, historique | Markdown / docx |

`docs/HISTORIQUE.md` retrace les décisions prises et leur ordre — à lire avant
toute décision d'architecture, pour ne pas revenir sur un arbitrage déjà tranché.

---

## 3. Commandes

```bash
npm run setup          # installe les dépendances de tous les sous-projets
npm run dev:backend    # API sur http://localhost:3000
npm run dev:landing    # landing page sur http://localhost:4173
npm run build:backend  # compile le backend
npm run lint           # vérifications disponibles
npm test               # tests (voir §7 : il n'y en a pas encore)
npm run audit:schema   # vérifie l'alignement entités TypeORM / migrations SQL
npm run db:provision   # crée la base, applique migrations + seed (psql requis)
```

Les scripts sous `scripts/` sont conçus pour ne jamais échouer sur un outil absent
(Flutter, psql…) : ils signalent et passent. C'est volontaire, pour qu'un
environnement partiellement provisionné reste utilisable.

---

## 4. Base de données — règle non négociable

**Les migrations SQL sont la source de vérité du schéma, pas TypeORM.**

`backend/src/config/database.config.ts` force `synchronize: false`. Ne le passe
jamais à `true` : le schéma contient des éléments que TypeORM ne sait pas
reproduire et écraserait silencieusement —

- colonnes `geography` (PostGIS) et leurs index spatiaux ;
- un **trigger qui crée automatiquement une rupture** quand une vente vide un stock ;
- des vues de tableaux de bord (`008_vues_tableaux_de_bord.sql`).

Toute évolution de schéma = un nouveau fichier numéroté dans
`database/migrations/`, jamais une modification d'un fichier déjà appliqué,
puis mise à jour de l'entité TypeORM correspondante pour rester aligné.

Application dans l'ordre :

```bash
for f in database/migrations/*.sql; do psql "$DATABASE_URL" -f "$f"; done
psql "$DATABASE_URL" -f database/seed/seed_dev.sql
```

---

## 5. Conventions de code

- **Le domaine est en français.** Entités, tables, colonnes, routes et DTO :
  `PointDeVente`, `points_de_vente`, `rupture`, `livreur_id`. Ne traduis pas en
  anglais — la cohérence avec le cahier des charges et le SQL prime.
- **Commentaires et messages utilisateur en français.**
- Backend : structure NestJS standard (`module` / `controller` / `service`),
  validation par `class-validator` sur les DTO, `ValidationPipe` global en mode
  `whitelist` + `forbidNonWhitelisted`.
- Autorisation : `JwtAuthGuard` + `RolesGuard` avec le décorateur `@Roles(...)`.
  Chaque rôle ne voit que son périmètre — voir le tableau §3 du cahier des charges.
- Mobile : Flutter + Riverpod, un dossier par rôle sous `lib/features/`.
- Landing : aucune dépendance externe hormis Google Fonts. Ne pas y introduire
  de framework ni d'étape de build.

---

## 6. Périmètres par rôle (à respecter dans toute nouvelle route)

| Rôle | Géolocalisation | Ruptures | Catalogue |
|---|---|---|---|
| Administrateur | réseau complet | toutes | tous |
| Fabricant | réseau qui lui est attribué | **son catalogue uniquement** | le sien |
| Livreur | points à proximité | catalogue du fabricant affilié | — |
| Point de vente | son point de vente | émission (signalement) | catalogue global |
| Agent recenseur | points qu'il gère | — | — |

Le filtrage par catalogue côté fabricant est une exigence métier, pas une
optimisation : un fabricant ne doit jamais voir la rupture d'un concurrent.

---

## 7. État réel du projet — à lire avant de promettre quoi que ce soit

Ce qui a été **vérifié par exécution** (2026-08-16) :

| Vérification | Résultat |
|---|---|
| `npm install` sur `backend/` | passe — 513 paquets |
| `tsc --noEmit` sur tout le backend | passe, aucune erreur de typage |
| `nest build` | passe, `backend/dist/` produit |
| Chargement de `bcrypt` (module natif) | **OK** — `require` + `hashSync` fonctionnent |
| Amorçage NestJS | **tous les modules s'initialisent** (App, TypeOrm, Passport, Jwt, Config) |
| Alignement entités ↔ migrations SQL | **18 tables, 119 colonnes, 0 désalignement** (`npm run audit:schema`) |
| Landing servie sur `:4173` | 200 sur HTML/CSS/JS, MIME corrects, 404 géré |
| Tests automatisés | **aucun** — 0 `.spec.ts`, 0 `_test.dart` |

Autrement dit : le seul obstacle au démarrage de l'API est **l'absence de base**.
Aucun autre blocage n'a été trouvé dans le code.

Ce qui reste **non vérifié** :

- Le backend **n'a jamais tourné contre une vraie base**. Il compile et s'amorce
  jusqu'à la connexion TypeORM, puis boucle sur « Unable to connect to the
  database ». Les erreurs d'exécution réelles restent à découvrir.
- Les migrations SQL n'ont **jamais été appliquées** sur une base réelle. L'audit
  statique confirme leur cohérence avec les entités, pas leur exécutabilité
  (ordre des dépendances, triggers, index spatiaux).
- Aucun endpoint HTTP n'a jamais répondu.
- Le mobile n'a **jamais été compilé** — SDK Flutter absent de l'environnement.
- **Aucun test automatisé n'existe.** `npm test` liste ce constat au lieu de
  sortir vert en silence. Si tu ajoutes une fonctionnalité, ajoute les tests
  avec (Jest côté backend, `flutter_test` côté mobile).
- Chaque interface mobile se limite à un **écran d'accueil**. Le reste de chaque
  maquette HTML reste à porter en Flutter.
- Trois intégrations sont déclarées mais **non branchées** : push FCM, paiement
  CinetPay, export Excel/PDF des statistiques.
- Le backend n'est pas déployé (cible : NindoHost).

Ne présente aucun de ces points comme fonctionnel sans l'avoir vérifié toi-même.

---

## 8. Configuration

Copie `backend/.env.example` vers `backend/.env` et renseigne les valeurs.
Variables lues par le code : `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_USER`,
`DATABASE_PASSWORD`, `DATABASE_NAME`, `JWT_SECRET`, `JWT_EXPIRATION`, `PORT`,
`NODE_ENV`.

Côté mobile, l'URL de l'API se passe à la compilation :
`flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000`
(`10.0.2.2` = hôte vu depuis l'émulateur Android ; `localhost` ne fonctionne pas).

**Ne commite jamais de `.env`, de clé CinetPay, de secret JWT ou de credential
NindoHost.** `.gitignore` couvre les cas courants, vérifie avant de committer.

---

## 9. Pièges connus

- Le token JWT porte **l'ID métier** en plus de l'ID utilisateur
  (`fabricantId` / `livreurId` / `pointDeVenteId` / `agentRecenseurId`). C'est un
  correctif d'architecture assumé ; il a nécessité la colonne `utilisateur_id`
  sur `points_de_vente` (migration `010`). Si tu touches à l'authentification,
  garde cette charge utile.
- Positions livreurs : historique horodaté dans une table dédiée, pas un simple
  champ « position courante ». Cadence prévue : 10 s en course active (ou 25-30 m
  parcourus), 1/min à l'arrêt, rien hors ligne.
- Un point de vente peut vendre des produits **hors catalogue Yalla** : ne pars
  pas du principe que toute vente référence un `produit_id`.
- Le mode hors-ligne est une exigence (réseau instable à Abidjan) : caisse et
  signalement doivent fonctionner sans connexion, avec synchronisation différée.
- La landing page masque ses éléments animés derrière une classe `js` posée par
  le script. Si tu retires ce mécanisme, la page reste blanche sans JavaScript.
- **`bcrypt` est un module natif.** Il a été vérifié comme fonctionnel ici
  (`require` + `hashSync` OK). Mais selon la configuration npm, son script
  `node-pre-gyp` peut être bloqué : l'installation réussit, puis `require('bcrypt')`
  échoue au démarrage. Si tu vois une erreur de binding au boot, c'est ça —
  réinstalle en autorisant les scripts, ou bascule sur `bcryptjs` (pur JS, même API).
- **Provisionner PostgreSQL sous Windows peut buter sur la locale.** Si le compte
  utilise une locale dont le nom contient une apostrophe typographique — cas de
  « French_Côte d'Ivoire.1252 », donc très probable sur ce projet — `initdb`
  échoue avec « failed to restore old locale ». C'est une limite du CRT Microsoft,
  pas un bug PostgreSQL, et Windows met la locale en cache pour toute la session :
  il faut la changer **puis rouvrir la session**. Sous Linux (donc chez Devin),
  le problème n'existe pas.
