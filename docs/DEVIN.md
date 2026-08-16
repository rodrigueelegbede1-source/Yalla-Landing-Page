# Configurer ce dépôt dans Devin

Devin lit [`AGENTS.md`](../AGENTS.md) à la racine : les conventions, contraintes
de schéma et pièges connus y sont déjà décrits. Ce document ne couvre que ce qui
se règle dans l'interface Devin elle-même.

---

## 1. Connecter le dépôt

Devin travaille depuis un dépôt Git distant. Poussez d'abord ce dossier :

```bash
git remote add origin git@github.com:VOTRE-COMPTE/yalla.git
git push -u origin main
```

Puis, dans Devin : **Settings → Repos → Connect repository**, et sélectionnez `yalla`.

---

## 2. Commandes de Repo Setup

Dans **Settings → Repos → yalla → Setup**, renseignez :

| Champ | Commande |
|---|---|
| Install / Setup | `npm run setup` |
| Lint | `npm run lint` |
| Test | `npm test` |
| Run (API) | `npm run dev:backend` |
| Run (vitrine) | `npm run dev:landing` |

Ces commandes sont volontairement tolérantes : si Flutter ou `psql` manquent dans
la machine Devin, elles le signalent et continuent, au lieu de faire échouer tout
le provisionnement. Le backend et la landing page restent utilisables sans eux.

---

## 3. Secrets

À déclarer dans **Settings → Secrets**, jamais dans le dépôt :

| Secret | Utilité | Requis |
|---|---|---|
| `DATABASE_PASSWORD` | connexion PostgreSQL | oui, pour lancer l'API |
| `JWT_SECRET` | signature des tokens | oui, pour lancer l'API |
| `CINETPAY_API_KEY`, `CINETPAY_SITE_ID` | paiement mobile | seulement quand l'intégration démarre |
| `FCM_SERVER_KEY` | notifications push | seulement quand l'intégration démarre |

`scripts/setup.sh` crée `backend/.env` depuis `.env.example` s'il est absent ;
les valeurs sensibles doivent venir des secrets Devin, pas du fichier committé.

---

## 4. Base de données dans l'environnement Devin

L'API ne démarre pas sans PostgreSQL **avec l'extension PostGIS** — les colonnes
`geography` et les index spatiaux en dépendent. Dans la machine Devin :

```bash
sudo apt-get install -y postgresql postgis
sudo service postgresql start
sudo -u postgres createdb yalla
sudo -u postgres psql -d yalla -c "CREATE EXTENSION IF NOT EXISTS postgis;"
npm run db:migrate
npm run db:seed
```

Vous pouvez ajouter ce bloc à la commande de setup une fois validé.

---

## 5. Knowledge à ajouter dans Devin

Trois points méritent d'être saisis comme *Knowledge*, car ils coûtent cher si
l'agent les découvre par l'échec :

1. **Le schéma vient des migrations SQL, pas de TypeORM.** `synchronize` reste à
   `false`. Une évolution = un nouveau fichier numéroté dans `database/migrations/`.
2. **Le domaine est en français** (`points_de_vente`, `rupture`, `livreur_id`).
   Ne pas angliciser les noms de tables, colonnes, entités ou routes.
3. **Rien n'a jamais été exécuté** dans ce dépôt : pas de build validé, pas de
   test, pas de déploiement. Les premières exécutions révéleront des erreurs —
   c'est attendu, ce n'est pas une régression introduite par l'agent.

---

## 6. Bons premiers tickets

Tâches cadrées, à faible risque, utiles pour calibrer l'agent sur ce dépôt :

- Faire démarrer l'API pour de bon : provisionner PostgreSQL + PostGIS, appliquer
  les migrations, corriger ce qui bloque au boot, documenter les correctifs.
- Ajouter une première suite de tests Jest sur `AuthService` (le module le plus
  critique et le plus isolé).
- Porter un écran de maquette HTML en Flutter — par exemple le signalement de
  rupture côté Point de vente, qui est le geste central du produit.
- Brancher l'export Excel/PDF des statistiques administrateur.

Évitez de lancer l'agent sur le paiement CinetPay ou le push FCM en premier :
les deux demandent des credentials tiers et un environnement de test externe.
