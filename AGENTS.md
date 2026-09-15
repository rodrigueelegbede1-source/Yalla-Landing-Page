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

Six rôles, six interfaces, des droits distincts :
`administrateur`, `fabricant`, `distributeur`, `livreur`, `point_de_vente`,
`agent_recenseur`.

Le `distributeur` a été introduit par la migration 011. C'est lui qui **reçoit
une rupture et agit dessus** ; le fabricant la voit en lecture, sur son seul
catalogue. Un fabricant qui livre lui-même possède son propre distributeur
(`auto_distribution`), ce qui évite tout cas particulier dans le code.

Le cahier des charges fait foi : `docs/01_cahier_des_charges/`.

---

## 2. Carte du dépôt

| Dossier | Contenu | Techno |
|---|---|---|
| `backend/` | API REST + WebSocket, 9 modules | NestJS 10, TypeScript |
| `database/` | Migrations SQL numérotées + seed de dev | PostgreSQL 15 + PostGIS |
| `mobile/` | Squelette app (auth + 1 écran par rôle) | Flutter / Dart |
| `landing/` | Site vitrine public | HTML/CSS/JS sans framework |
| `maquettes/` | 6 prototypes HTML cliquables, un par rôle | HTML statique |
| `docs/` | Cahier des charges, modèle de données, stack, historique | Markdown / docx |

`docs/HISTORIQUE.md` retrace les décisions prises et leur ordre — à lire avant
toute décision d'architecture, pour ne pas revenir sur un arbitrage déjà tranché.

---

## 3. Commandes

```bash
npm run setup          # installe les dépendances de tous les sous-projets
npm run dev:backend    # API sur http://localhost:3000
npm run dev:landing    # landing page sur http://localhost:4180
npm run build:backend  # compile le backend
npm run lint           # vérifications disponibles
npm test               # tests — suite SQL d'escalade, plus l'inventaire backend/mobile (§7)
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
npm run db:provision     # base + PostGIS + migrations + seed, d'un coup
# ou, sur une base déjà créée :
npm run db:migrate
npm run db:seed
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
| Fabricant | réseau qui lui est attribué | son catalogue uniquement, **en lecture** | le sien |
| Distributeur | ses points de vente et sa flotte | celles qu'il peut prendre, **en action** | marques qu'il porte |
| Livreur | points à proximité | périmètre de son distributeur | — |
| Point de vente | son point de vente | émission (signalement) | catalogue global |
| Agent recenseur | points qu'il gère | — | — |

Le filtrage par catalogue côté fabricant est une exigence métier, pas une
optimisation : un fabricant ne doit jamais voir la rupture d'un concurrent.

**Qui peut prendre quelle rupture est décidé par la vue
`v_acces_rupture_distributeur`, pas par du code.** Ne réimplémente pas cette
règle en TypeScript, interroge la vue. Elle répond pour les deux cercles
(`attribue` dès le signalement, `elargi` après escalade), et c'est elle que
consulte aussi l'UPDATE conditionnel de prise en charge.

---

## 7. État réel du projet — à lire avant de promettre quoi que ce soit

Ce qui a été **vérifié par exécution** (2026-08-16, complété le 2026-09-15) :

| Vérification | Résultat |
|---|---|
| `npm install` sur `backend/` | passe — 513 paquets |
| `tsc --noEmit` sur tout le backend | passe, aucune erreur de typage |
| `nest build` | passe, `backend/dist/` produit |
| Chargement de `bcrypt` (module natif) | **OK** — `require` + `hashSync` fonctionnent |
| Amorçage NestJS | **tous les modules s'initialisent** (App, TypeOrm, Passport, Jwt, Config) |
| Migrations appliquées sur une vraie base | **les 11 passent** sur PostgreSQL 17 + PostGIS 3.6, base créée de zéro |
| Seed de développement | **passe** — après correction de 5 `INSERT` qui omettaient `mot_de_passe_hash` |
| API connectée à la base | **démarre et sert** — « Nest application successfully started », toutes les routes montées |
| Endpoints HTTP | **répondent** — login, carnet distributeur, passe d'escalade, prise en charge (200 puis 409) |
| Suite SQL d'escalade | **10 cas verts** (`npm test`) |
| Alignement entités ↔ migrations SQL | **19 tables, 133 colonnes, 0 désalignement** (`npm run audit:schema`, revérifié le 2026-09-15 après `011`) |
| Landing servie sur `:4180` | 200 sur HTML/CSS/JS, MIME corrects, 404 géré |
| Tests automatisés | **suite SQL uniquement** — `database/tests/test_escalade.sql`, 10 cas. Toujours 0 `.spec.ts`, 0 `_test.dart` |

La chaîne complète a donc tourné une fois de bout en bout : base provisionnée,
migrations appliquées, seed chargé, API démarrée, endpoints interrogés. Trois
bugs que l'analyse statique ne pouvait pas voir sont sortis à cette occasion,
tous corrigés (voir §9).

Ce qui reste **non vérifié** :

- La validation du 2026-09-15 a été faite sur **PostgreSQL 17 + PostGIS 3.6**,
  alors que la cible documentée est PostgreSQL 15. Rien dans le schéma n'est
  propre à la 17, mais l'écart est réel et mérite d'être rejoué sur la version
  cible avant déploiement.
- Elle a tourné sur un **cluster jetable en locale C**, monté hors de
  `Program Files` faute de droits administrateur. Le comportement en locale
  française reste donc non testé — voir le piège `initdb` au §9, qui est
  précisément ce qui a empêché l'installation standard d'aboutir.
- Les modules non exercés par ce passage (caisse, notifications, livraisons,
  transactions) n'ont toujours **aucun endpoint testé**.
- Le mobile n'a **jamais été compilé** — SDK Flutter absent de l'environnement.
- **Le backend et le mobile n'ont toujours aucun test.** `npm test` liste ce
  constat au lieu de sortir vert en silence. Si tu ajoutes une fonctionnalité,
  ajoute les tests avec (Jest côté backend, `flutter_test` côté mobile).
- Il existe en revanche une **suite SQL** : `database/tests/test_escalade.sql`
  vérifie par exécution le routage des ruptures, les deux cercles d'accès, la
  non-réescalade, la concurrence entre deux preneurs et la péremption. Elle
  tourne dans une transaction close par `ROLLBACK`, donc rejouable à l'infini
  sur la même base. Elle a besoin d'une base provisionnée avec le seed ;
  `npm test` signale et passe quand `psql` ou la base manquent.
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

**Deux conventions coexistent, ne les confonds pas** : l'application NestJS lit
`DATABASE_*` depuis `backend/.env`, tandis que les scripts SQL (`db:provision`,
`db:migrate`, `db:seed`) passent par `psql`, qui lit les variables `PG*`
standard (`PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`). Renseigner
seulement `backend/.env` ne suffit donc pas à diriger `psql` vers la bonne base.

Côté mobile, l'URL de l'API se passe à la compilation :
`flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000`
(`10.0.2.2` = hôte vu depuis l'émulateur Android ; `localhost` ne fonctionne pas).

**Ne commite jamais de `.env`, de clé CinetPay, de secret JWT ou de credential
NindoHost.** `.gitignore` couvre les cas courants, vérifie avant de committer.

---

## 9. Pièges connus

- **La landing est publiée deux fois, et `landing/` reste la source unique.**
  Le site en ligne est servi par GitHub Pages depuis le dépôt public
  `rodrigueelegbede1-source/Yalla-Landing-Page`, qui n'est qu'un **miroir** du
  dossier `landing/` de ce dépôt. Ne modifie jamais le miroir directement : il
  est régénéré par `git subtree split --prefix landing -b gh-pages` puis poussé.
  Un correctif appliqué au miroir serait écrasé à la publication suivante.
  Pourquoi ce détour : GitHub Pages n'est pas disponible sur un dépôt privé avec
  un compte Free, et le dépôt `yalla` doit rester privé. Le miroir ne contient
  que la landing, c'est-à-dire du contenu déjà public par nature.
  Le déploiement Vercel (`landing-page-yalla`) vise le même dossier mais reste
  inaccessible de l'extérieur tant que la protection de déploiement est active.

- **Ne déploie jamais `backend/` sur Vercel, et vérifie le « Root Directory ».**
  Le 15/09/2026, le projet Vercel a été importé avec Root Directory sur
  `backend/`. Vercel a servi le dossier en statique et **tout le code source de
  l'API est devenu public** (`/src/main.ts`, `/src/modules/auth/auth.service.ts`,
  `/src/config/database.config.ts` répondaient 200 sur une URL ouverte). Aucun
  secret n'a fuité, `backend/.env` étant ignoré par git donc absent du
  déploiement. Le réglage correct est **Root Directory sur `./`** : le
  `vercel.json` de la racine publie alors `landing/` et rien d'autre.
  Corrigé le 15/09/2026 : `rootDirectory` est repassé à la racine et
  `framework` à `null`. Le garde-fou `backend/.vercelignore` posé en urgence ce
  jour-là a été retiré, devenu inutile.
  Sur le fond, l'API n'a pas sa place sur Vercel : socket.io, la connexion
  PostgreSQL persistante et le job d'escalade en `setInterval` sont incompatibles
  avec le serverless. La cible reste NindoHost.

**Les trois premiers viennent du passage en conditions réelles du 2026-09-15.
Aucun n'était visible au typage ni à l'audit de schéma.**

- **`repo.query()` sur un `UPDATE ... RETURNING` ne renvoie pas les lignes.** Le
  pilote postgres de TypeORM renvoie `[lignes, nombreAffecté]`. Tester
  `.length === 0` sur le résultat brut donne donc toujours 2, jamais 0 : un
  UPDATE conditionnel qui ne touche aucune ligne passe pour un succès. C'est ce
  qui rendait muet le 409 de `prendre-en-charge`. Normalise le résultat
  (`Array.isArray(r?.[0]) ? r[0] : r`) avant de compter.
- **Ne lis jamais `process.env` dans un décorateur `@Module`.** Les arguments de
  `JwtModule.register({...})` sont évalués au chargement du fichier, avant que
  `ConfigModule.forRoot()` d'app.module ait lu `backend/.env`. La valeur retombe
  sur le défaut, tandis qu'un provider instancié plus tard lit la vraie. Le
  symptôme est déroutant : `/auth/login` délivre un token valide et toutes les
  routes protégées répondent 401 dessus. Utilise `registerAsync` + `ConfigService`.
- **`utilisateurs.mot_de_passe_hash` est NOT NULL.** Cinq `INSERT` du seed
  l'omettaient : le seed échouait au deuxième utilisateur et n'avait donc jamais
  pu s'appliquer. Si tu ajoutes un compte, n'oublie pas la colonne.

- **Une rupture peut naître sans passer par NestJS.** Le trigger de caisse de
  `006` insère directement dans `ruptures` quand une vente vide un stock. Toute
  logique qui doit s'appliquer à *toutes* les ruptures va donc en SQL, pas dans
  un service. C'est pourquoi la résolution du destinataire est le trigger
  `trg_ruptures_resout_destinataire` (`011`) et non du TypeScript.
- **`prendre-en-charge` doit rester un UPDATE conditionnel.** Il filtre sur
  `statut = 'signalee'` et renvoie 409 quand aucune ligne n'est touchée. Un
  simple `repo.update()` laisserait deux livreurs partir sur la même course en
  croyant chacun l'avoir obtenue. Même chose pour toute future prise de course.
- **L'escalade tourne dans le processus de l'API** (`EscaladeService`, un
  `setInterval` de 5 min qui appelle `escalader_ruptures_en_attente()`). Avec
  plusieurs instances, elles la déclencheront toutes : la fonction SQL est
  idempotente, donc sans dégât, mais il faudra basculer sur pg_cron ou un verrou
  consultatif le jour du passage à l'échelle.
- **Les délais d'escalade et de péremption sont des fonctions SQL**
  (`delai_escalade()` = 2 h, `delai_peremption()` = 24 h), pas des constantes
  applicatives. Les changer se fait par `CREATE OR REPLACE`, sans migration ni
  redémarrage. Ne les recopie pas en dur côté TypeScript ou Flutter.
- **L'escalade ne franchit jamais la frontière de la marque.** Le cercle élargi
  ne s'ouvre qu'aux distributeurs qui portent déjà le même fabricant dans la même
  commune. C'est une protection des accords de territoire, pas une optimisation
  de requête : ne l'élargis pas sans instruction explicite.
- **Supprimer une colonne dont dépend une vue échoue.** `011` a dû redéfinir
  `v_chiffre_affaires_par_fabricant` et `v_chiffre_affaires_par_livreur` avant de
  pouvoir retirer `livreurs.fabricant_id`. Vérifie les vues de `008` avant tout
  `DROP COLUMN`.

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
- **Le mode hors-ligne a été retiré du périmètre** (décision du 2026-08-16).
  Yalla suppose une connexion active : une rupture n'a de valeur que transmise
  immédiatement. Ne réintroduis pas de base locale, de file d'attente de
  synchronisation ni de « mode dégradé » sans instruction explicite — les
  dépendances correspondantes ont été retirées de `mobile/pubspec.yaml`.
- La landing page masque ses éléments animés derrière une classe `js` posée par
  le script. Si tu retires ce mécanisme, la page reste blanche sans JavaScript.
- **`bcrypt` est un module natif.** Il a été vérifié comme fonctionnel ici
  (`require` + `hashSync` OK). Mais selon la configuration npm, son script
  `node-pre-gyp` peut être bloqué : l'installation réussit, puis `require('bcrypt')`
  échoue au démarrage. Si tu vois une erreur de binding au boot, c'est ça —
  réinstalle en autorisant les scripts, ou bascule sur `bcryptjs` (pur JS, même API).
- **Provisionner PostgreSQL sous Windows bute effectivement sur la locale.**
  Confirmé le 2026-09-15 sur la machine du projet : l'installateur EDB s'arrête
  sur `initdb: erreur : le nom de la locale « French_Côte d'Ivoire.1252 »
  contient des caractères non ASCII`. Contournement qui fonctionne sans toucher
  aux réglages Windows : lancer `initdb` à la main avec `--locale=C`, ce qui
  évite la lecture de la locale système. C'est ainsi que la base de validation a
  été montée.
- **Détail historique de ce piège.** Si le compte
  utilise une locale dont le nom contient une apostrophe typographique — cas de
  « French_Côte d'Ivoire.1252 », donc très probable sur ce projet — `initdb`
  échoue avec « failed to restore old locale ». C'est une limite du CRT Microsoft,
  pas un bug PostgreSQL, et Windows met la locale en cache pour toute la session :
  il faut la changer **puis rouvrir la session**. Sous Linux (donc chez Devin),
  le problème n'existe pas.
