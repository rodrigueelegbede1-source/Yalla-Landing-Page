# Yalla — Backend API (NestJS)

API qui expose le schéma PostgreSQL/PostGIS défini dans `yalla-backend/database`
(dossier livré séparément) aux 5 interfaces déjà maquettées.

## Démarrage

```bash
npm install
cp .env.example .env   # puis renseigner les identifiants de connexion à la base
```

Assurez-vous d'avoir exécuté au préalable les migrations SQL du dossier
`database/migrations` (voir son propre README) sur la base pointée par `.env`.

```bash
npm run start:dev
```

L'API démarre sur `http://localhost:3000` (configurable via `PORT`).

## Organisation

```
src/
  entities/          Entités TypeORM, une par table du schéma SQL
  config/             Configuration TypeORM (synchronize désactivé à dessein)
  common/              Guards (JWT, rôles) et décorateur @Roles
  gateways/            Passerelle WebSocket temps réel (positions, flux d'activité)
  modules/
    auth/              Connexion, émission de JWT
    points-de-vente/   Enregistrement, activation, retrait
    fabricants/         Réseau attribué, chiffre d'affaires
    produits/            Catalogue par fabricant, catalogue global
    livreurs/            Position en temps réel, statut en ligne
    ruptures/            Signalement manuel, recherche de proximité
    livraisons/          Démarrage, fin de course (résout la rupture liée)
    caisse/              Ventes / lignes de vente — déclenche le trigger SQL de rupture automatique
    notifications/       Envoi, sondages
```

## Choix d'architecture à connaître

- **`synchronize: false` volontaire** — le schéma est piloté uniquement par les
  migrations SQL déjà livrées (extensions PostGIS, triggers métier). Ne jamais
  activer la synchronisation automatique de TypeORM sur ce projet : elle
  ignorerait les triggers et pourrait tenter de les supprimer.
- **Colonnes `geography` non mappées directement sur les entités** — pour
  `points_de_vente.position`, `livreurs.position` et `positions_livreurs.position`,
  le mapping ORM direct sur un type PostGIS est source d'erreurs subtiles. Ces
  colonnes sont lues/écrites via des requêtes SQL brutes (`ST_MakePoint`,
  `ST_X`/`ST_Y`, `ST_Distance`) dans les services concernés — voir
  `PointsDeVenteService`, `LivreursService`, `RupturesService`.
- **Le trigger SQL reste la source de vérité pour la rupture automatique** —
  `CaisseService.enregistrerVente` insère les lignes de vente et laisse le
  trigger `trg_lignes_vente_decremente_stock` (migration 006) décrémenter le
  stock et créer la rupture si besoin ; le service se contente de détecter les
  nouvelles ruptures pour les diffuser en temps réel, sans dupliquer la règle.
- **Résolution livreur/fabricant/point de vente ↔ utilisateur** — le JWT
  porte désormais `idMetier` en plus de l'ID utilisateur (`sub`), résolu une
  seule fois au login par `AuthService.resoudreIdMetier` (jointure vers
  `fabricants`, `livreurs`, `agents_recenseurs` ou `points_de_vente` selon le
  rôle). Les endpoints livreur (position, démarrage de livraison) lisent
  directement `req.user.idMetier` plutôt que de refaire cette résolution à
  chaque appel. Nécessite la migration `010_utilisateur_point_de_vente.sql`
  (ajoutée après coup — `points_de_vente` n'avait pas de lien vers un compte
  de connexion dans le schéma initial).

## Ce qui n'est pas encore branché

- **Envoi push réel (FCM)** — `NotificationsService.envoyer` crée la notification
  en base et diffuse l'événement en WebSocket, mais n'appelle pas encore
  l'API Firebase Cloud Messaging (nécessite de stocker un token d'appareil par
  utilisateur, absent du schéma v1).
- **Paiement CinetPay** — l'entité `Transaction` et le champ
  `reference_cinetpay` existent, mais aucun module n'appelle encore l'API
  CinetPay ni ne traite ses webhooks de confirmation.
- **Export Excel/PDF** des statistiques (maquette Administrateur) — les vues
  SQL qui alimenteraient l'export existent (`v_chiffre_affaires_par_fabricant`,
  etc.), mais la génération de fichier côté API reste à écrire (`exceljs`,
  `pdfkit`, comme indiqué dans `Yalla_Stack_Technique.md`).
- **Tests** — aucun test automatisé n'a été écrit à ce stade.
- **Exécution non vérifiée** — comme pour le schéma SQL, cet environnement n'a
  pas d'accès réseau pour installer les dépendances npm et faire tourner l'API ;
  le code a été relu attentivement mais son premier démarrage réel se fera de
  votre côté.
