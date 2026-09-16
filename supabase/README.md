# Base Yalla sur Supabase

Tout le produit tient ici. Le schéma, les règles d'accès, la logique métier et
les tâches planifiées vivent dans la base, pas dans l'application. C'est un choix
imposé par le produit lui-même : la rupture la plus importante, celle que la
caisse déclenche quand une vente vide un stock, est créée par un **trigger**.
Aucun client ne la voit passer. Une règle qui doit s'appliquer à *toutes* les
ruptures ne peut donc pas vivre ailleurs qu'en SQL.

---

## Mise en place, une seule fois

### 1. Créer le projet

Sur [supabase.com](https://supabase.com), nouveau projet.

**Région : Paris (eu-west-3)**, la plus proche d'Abidjan. Un projet créé aux
États-Unis ajoute environ 150 ms à chaque requête, ce qui se sent sur une caisse
utilisée toute la journée.

Notez la référence du projet, visible dans l'URL du tableau de bord.

### 2. Relier le dépôt

```bash
supabase link --project-ref <la-référence>
```

### 3. Activer les extensions

Dans le tableau de bord, Database puis Extensions, activez :

- **postgis** — colonnes `geography`, index spatiaux, tri par distance réelle
- **pg_cron** — escalade des ruptures et purges

Sans PostGIS, la première migration échoue immédiatement.

### 4. Appliquer le schéma

```bash
npm run db:verifier   # valide d'abord en local, sur une base jetable
npm run db:push       # puis applique sur le projet distant
```

`db:verifier` n'est pas une précaution de confort. Un `db:push` qui échoue à
mi-parcours laisse la base distante avec une partie des migrations appliquées et
pas les autres, dans un état dont on ne sort pas proprement.

### 5. Activer le hook d'authentification

**Étape à ne pas sauter.** Sans elle, l'application se connecte mais n'obtient
ni rôle ni identifiant métier, et n'affiche donc aucune interface.

Elle s'automatise, ce qui évite de l'oublier :

```bash
curl -X PATCH "https://api.supabase.com/v1/projects/<ref>/config/auth" \
  -H "Authorization: Bearer <jeton de compte>" \
  -H "Content-Type: application/json" \
  -d '{"hook_custom_access_token_enabled": true,
       "hook_custom_access_token_uri": "pg-functions://postgres/public/custom_access_token_hook"}'
```

Ou à la main : Authentication, Hooks, `Customize Access Token (JWT) Claims`,
Postgres function, `public.custom_access_token_hook`.

Ce hook lit la ligne `utilisateurs` correspondant au compte et injecte
`user_role`, `id_metier`, `utilisateur_id` et `nom` dans le jeton. Les politiques
RLS les lisent ensuite sans requête supplémentaire, ce qui compte quand une
politique filtre des milliers de ruptures.

### 6. Récupérer les clés pour l'application

Tableau de bord, Project Settings, API. L'application se lance avec :

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGci...
```

La clé « anon » est **publique par conception** : elle est lisible dans
n'importe quel APK décompilé, et c'est normal. Ce n'est pas elle qui protège les
données, ce sont les politiques RLS.

La clé **service_role**, elle, contourne RLS. Elle ne doit jamais entrer dans
l'application mobile, ni dans le dépôt, ni dans une capture d'écran.

---

## Créer un compte

Un compte Yalla se crée en deux temps, parce que Supabase Auth et le métier sont
deux choses distinctes.

**1. La ligne métier**, créée par l'agent recenseur ou l'administrateur :

```sql
INSERT INTO utilisateurs (nom, telephone, role)
VALUES ('Aya Kouassi', '+2250745000000', 'point_de_vente')
RETURNING id;

INSERT INTO points_de_vente (nom, type_activite, commune, position, utilisateur_id, ...)
VALUES ('Supérette Akwaba', 'superette', 'Cocody',
        ST_SetSRID(ST_MakePoint(-3.9862, 5.3599), 4326)::geography, '<id>', ...);
```

**2. Le compte de connexion**, via l'API d'administration, avec l'adresse
technique dérivée du numéro :

```bash
curl -X POST 'https://xxxx.supabase.co/auth/v1/admin/users' \
  -H "apikey: <service_role>" \
  -H "Authorization: Bearer <service_role>" \
  -H "Content-Type: application/json" \
  -d '{"email":"2250745000000@yalla.ci","password":"<mot de passe remis au gérant>","email_confirm":true}'
```

Puis on relie les deux :

```sql
SELECT rattacher_compte_auth('+2250745000000', '<id retourné par l''API>');
```

L'adresse technique se calcule avec `email_technique('+2250745000000')`, qui rend
`2250745000000@yalla.ci`. Aucun courriel n'y est jamais envoyé : c'est une clé,
pas une boîte. L'application fait la même conversion côté Dart, et les deux
implémentations sont verrouillées par des tests.

Ce détour évite le SMS. Supabase n'accepte un numéro comme identifiant que
vérifié par SMS, et chaque SMS coûte de l'argent à chaque connexion. Or les
comptes sont remis en main propre lors du recensement, pas créés en libre-service.

---

## Les fichiers

| Fichier | Rôle |
|---|---|
| `migrations/2026091600xx_*` | Le schéma d'origine, porté sans modification |
| `migrations/*_auth_supabase.sql` | Lien vers `auth.users`, hook, conversion du numéro |
| `migrations/*_rls_perimetres.sql` | **Les périmètres par rôle. La sécurité du produit tient là.** |
| `migrations/*_rpc_actions_metier.sql` | Les actions qui écrivent, avec leurs verrous |
| `migrations/*_realtime_et_cron.sql` | Diffusion temps réel et tâches planifiées |
| `migrations/*_vues_applicatives.sql` | Ce que les trois écrans consomment |
| `seed.sql` | Réseau de démonstration, développement uniquement |
| `tests/verifier-migrations.sh` | Applique et teste tout sur un PostgreSQL ordinaire |
| `tests/stubs_supabase_local.sql` | Simule Supabase pour permettre ce test |

---

## Règles à ne pas enfreindre

**Une migration appliquée ne se modifie jamais.** Toute évolution est un nouveau
fichier horodaté.

**Toute table du schéma public est sous RLS.** Sans politique, RLS refuse tout,
ce qui est le bon défaut : une table oubliée devient inaccessible, pas ouverte.
`db:verifier` échoue si une table y échappe.

**Toute vue est en `security_invoker = on`.** Sans cette option, une vue
s'exécute avec les droits de son propriétaire et contourne silencieusement
toutes les politiques. `db:verifier` échoue aussi là-dessus.

**Un identifiant métier ne se lit jamais depuis le client.** L'ancienne API le
prenait dans l'URL ou le corps de la requête, ce qui ouvrait sept fuites réelles,
dont un fabricant capable de lire le chiffre d'affaires d'un concurrent.
L'identité se lit dans le jeton, par `auth_id_metier()`, et nulle part ailleurs.

**Une fonction `SECURITY DEFINER` ne passe pas par RLS.** Celles de
`rpc_actions_metier.sql` en sont toutes, par nécessité. Chacune vérifie donc le
rôle et la propriété de la ressource dès sa première ligne. Si vous en ajoutez
une, faites de même, sinon vous ouvrez une porte dérobée.

---

## Deux pièges rencontrés au premier déploiement

Les deux ont le même symptôme, un échec net qui ne dit pas sa cause, et la même
origine : **ce qui passe sous `psql` ne passe pas forcément sur Supabase**.

### Une valeur d'énumération ne s'utilise pas dans la transaction qui l'ajoute

`supabase db push` enveloppe chaque fichier dans une transaction unique, alors
que `psql -f` valide instruction par instruction. Une migration qui ajoute une
valeur d'énumération puis s'en sert passe donc en local et échoue en ligne
(SQLSTATE 55P04), en laissant la base distante à mi-chemin.

Toute nouvelle valeur d'énumération va dans son propre fichier. Le harnais local
applique désormais chaque migration avec `--single-transaction`, ce qui
reproduit le comportement de Supabase et attrape le problème avant le déploiement.

### Le hook ne voit pas le schéma `public`

Symptôme : toute connexion échoue en HTTP 500 avec « Error running hook URI ».
La réponse de l'API ne dit rien de plus. Seuls les journaux d'authentification
du projet donnent la cause :

    ERROR: type "role_utilisateur" does not exist (SQLSTATE 42704)

Le hook n'est pas exécuté par `postgres` mais par `supabase_auth_admin`, dont
le `search_path` ne contient pas `public`. La fonction marche parfaitement
appelée à la main, et échoue en production.

Toute fonction appelée par un service Supabase porte donc `SET search_path =
public` **et** qualifie ses objets. Il lui faut aussi une politique RLS dédiée
si elle lit une table protégée : le GRANT seul ne suffit pas, RLS filtre ensuite.

En cas de doute, les journaux se lisent ainsi :

```bash
curl -H "Authorization: Bearer <jeton>"   "https://api.supabase.com/v1/projects/<ref>/analytics/endpoints/logs.all?sql=<requête encodée>"
```

---

## Ce qui n'est pas vérifiable en local

`npm run db:verifier` couvre la syntaxe, l'ordre des dépendances, les triggers,
les fonctions et la présence des politiques. Il ne couvre pas :

- le comportement réel des politiques RLS sous une identité Supabase
- le hook d'émission de jeton, appelé par le service d'authentification
- la diffusion Realtime
- l'exécution effective des tâches `pg_cron`

Ces quatre points exigent un vrai projet. À vérifier une fois le projet créé :

```sql
SELECT * FROM cron.job;                         -- trois tâches attendues
SELECT * FROM pg_policies WHERE schemaname = 'public';  -- 34 politiques
```
