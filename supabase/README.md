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

### 7. Déployer la fonction Edge de création de comptes

```bash
supabase functions deploy creer-compte
```

Sans elle, ni l'agent recenseur ni le distributeur ne peuvent créer de compte, et
le réseau se remplit à la main en SQL.

---

## Créer un compte

**Les comptes se créent dans l'application**, pas en SQL. L'agent recenseur
inscrit les boutiques et les distributeurs, le distributeur enrôle ses livreurs.
Chacun reçoit son numéro et un mot de passe court, affiché une seule fois et
remis en main propre.

Le chemin technique passe par la fonction Edge `creer-compte`, pour une raison
qui n'est pas négociable : créer un compte dans `auth.users` exige la clé
`service_role`, qui contourne RLS et ne peut donc jamais entrer dans un APK.
La fonction enchaîne trois choses :

1. elle crée le compte de connexion avec `service_role`, côté serveur ;
2. elle appelle `creer_compte_metier` **avec le jeton de l'appelant**, si bien
   que `auth_role()` rend son rôle réel et que le contrôle de périmètre
   s'applique pour de bon ;
3. si ce contrôle refuse, elle supprime le compte qu'elle vient de créer. Un
   compte de connexion sans rôle se connecterait sans accès à rien, sans aucun
   moyen de s'en apercevoir.

Qui peut créer quoi, vérifié en SQL et couvert par `test_gestion_reseau.sql` :

| Créateur | Peut créer |
|---|---|
| Administrateur | tout |
| Agent recenseur | points de vente, distributeurs |
| Distributeur | livreurs, dans sa propre flotte uniquement |

### Les deux premiers comptes

Personne ne peut créer le premier compte depuis l'application, puisqu'il faut
déjà un compte pour s'y connecter. Un script couvre ce seul cas :

```bash
bash scripts/amorcer-pilote.sh
```

Il crée un administrateur et un agent recenseur, affiche leurs identifiants une
fois, et refuse de s'exécuter si la base contient déjà des comptes. Tout le reste
du réseau se crée ensuite depuis le téléphone.

### L'adresse technique

Le numéro sert d'identifiant, converti en adresse technique par
`email_technique('0745000000')`, qui rend `2250745000000@yalla.ci`. Aucun
courriel n'y est jamais envoyé : c'est une clé, pas une boîte.

Ce détour évite le SMS. Supabase n'accepte un numéro comme identifiant que
vérifié par SMS, et chaque SMS coûte de l'argent à chaque connexion. Or les
comptes sont remis en main propre lors du recensement, pas créés en libre-service.

**La normalisation existe en quatre exemplaires** : `normaliser_telephone()` en
SQL, `normaliserTelephone` en Dart, son homologue dans la fonction Edge, et une
quatrième dans le script d'amorçage. Les quatre doivent rendre exactement
`2250745000000`, treize chiffres sans `+`. Si l'une diverge, un compte se crée
sous une adresse et se connecte sous une autre, et rien dans le message d'erreur
ne le dit. Une version de la fonction Edge préfixait un `+` : les tests
verrouillent désormais la forme canonique.

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

## Quatre pièges rencontrés en déployant

Ils ont tous le même symptôme, un échec net qui ne dit pas sa cause, et la même
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

### Une politique ne doit jamais lire la table qu'elle protège

Symptôme : `infinite recursion detected in policy for relation "..."`
(SQLSTATE 42P17), et **plus aucune lecture de la table ne passe, pour aucun
rôle**. Les politiques PERMISSIVE sont combinées par OU, donc une seule qui
boucle fait tomber la table entière, y compris pour des rôles qui n'ont rien à
voir avec elle.

La sous-requête doit passer par une fonction `SECURITY DEFINER`, qui s'exécute
hors RLS et rompt la boucle. C'est ce que font `distributeur_voit_rupture`,
`communes_du_distributeur` et leurs voisines.

Ces fonctions **gardent leur droit `EXECUTE` sur `authenticated`** : une
expression de politique s'évalue sous l'identité qui interroge, et un `REVOKE`
rendrait la politique inapplicable. Elles ne doivent donc jamais rendre autre
chose qu'un booléen ou une donnée sans valeur commerciale.

`npm run db:verifier` échoue désormais si une politique lit sa propre table.
Le contrôle a été ajouté parce que le harnais ne pouvait pas voir la faute : il
vérifiait que les politiques existent, jamais qu'elles s'exécutent, faute
d'identité. Le bogue n'est apparu qu'en lançant l'application sur un appareil.

### PostgREST garde en cache un schéma périmé

Symptôme le plus déroutant des quatre : `curl: (52) Empty reply from server`,
sans code HTTP, sans journal. Une fonction fraîchement déployée existe bien en
base, répond parfaitement sous `psql`, et l'API ferme la connexion sans rien
dire.

PostgREST tient un cache du schéma et ne le relit pas de lui-même après un
`supabase db push`. Il faut le lui demander :

```sql
NOTIFY pgrst, 'reload schema';
```

C'est ce que fait `npm run db:deploy`, qui pousse les migrations **et** recharge
le cache. Utilisez-le plutôt que `db:push` seul.

À ne pas confondre avec les coupures intermittentes : environ un appel sur dix
se termine aussi en `(52)` sur ce projet, y compris sur des lectures triviales.
Si le rechargement ne change rien, réessayez avant de chercher un bogue.

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
