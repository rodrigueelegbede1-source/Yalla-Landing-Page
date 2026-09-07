# Projet YALLA — résumé et historique des décisions

Ce dossier regroupe tout ce qui a été produit pour l'application **Yalla**,
plateforme mobile 3 en 1 : géolocalisation en temps réel (type Uber),
notifications de ruptures de stock, et caisse enregistreuse (type Loyverse).
Lancement prévu sur Abidjan, Côte d'Ivoire, en iOS et Android.

## Comment lire ce dossier

| Dossier | Contenu |
|---|---|
| `01_cahier_des_charges/` | Version structurée du cahier des charges d'origine |
| `02_modele_de_donnees/` | Schéma conceptuel : entités, champs, règles métier |
| `03_stack_technique/` | Choix techniques justifiés (mobile, backend, base, paiement, hébergement) |
| `04_maquettes/` | 5 prototypes HTML cliquables, un par interface |
| `05_base_de_donnees/` | Migrations SQL exécutables (PostgreSQL + PostGIS) |
| `06_backend_api/` | API NestJS qui expose ce schéma |
| `07_mobile/` | Squelette Flutter connecté à cette API |

## Décisions prises, dans l'ordre

1. **Cahier des charges** structuré à partir du document fourni (Appli_YALLA.docx) :
   5 interfaces — Administrateur, Fabricant, Livreur, Point de vente, Agent recenseur.
2. **Maquettes cliquables** des 5 interfaces, identité visuelle cohérente
   (navy / amber / teal, polices Sora + Inter + IBM Plex Mono).
3. **Modèle de données** défini, puis complété par ces décisions :
   - Historique horodaté des positions livreurs (table dédiée, pas juste un champ courant)
   - Une vente qui vide un stock déclenche automatiquement une rupture
   - Un point de vente peut vendre des produits hors catalogue Yalla
4. **Stack technique** : Flutter, NestJS, PostgreSQL + PostGIS, Socket.io,
   Firebase Cloud Messaging, Google Maps SDK, **CinetPay** (paiement),
   **NindoHost** (hébergement).
5. **Fréquence de mise à jour des positions livreurs** : 10 s en course active
   (ou 25-30 m parcourus), 1/min à l'arrêt, rien hors ligne.
6. **Développement réel démarré** : schéma SQL exécutable, backend NestJS
   (9 modules), squelette Flutter (authentification réelle + un écran
   fonctionnel par rôle, câblé sur l'API).
7. **Correctif d'architecture** : le token de connexion renvoie désormais
   l'ID métier (fabricantId/livreurId/pointDeVenteId/agentRecenseurId) en plus
   de l'ID utilisateur — a nécessité l'ajout d'un lien `utilisateur_id` sur
   `points_de_vente`, absent du schéma initial.

8. **Mode hors-ligne retiré du périmètre** (2026-08-16). Le cahier des charges
   initial prévoyait que la caisse et le signalement continuent de fonctionner
   sans réseau, avec synchronisation différée. Cette exigence est abandonnée :
   Yalla repose sur le temps réel, et une rupture stockée localement pendant
   des heures perd sa raison d'être. Conséquences appliquées — dépendances
   `drift`, `sqlite3_flutter_libs`, `path_provider` et `path` retirées de
   `mobile/pubspec.yaml` (elles n'étaient utilisées nulle part), mentions
   supprimées de la landing, des maquettes et du dossier stack technique.
   Le corollaire à traiter : soigner le comportement en réseau faible plutôt
   que de masquer la coupure.

## Où ça en est, honnêtement

- Le code (base de données, backend, mobile) a été écrit avec soin mais
  **jamais exécuté** dans cet environnement, faute d'accès réseau pour
  installer PostgreSQL/PostGIS, les dépendances npm ou le SDK Flutter — le
  premier test réel se fera de votre côté ou via un développeur.
- Chaque interface mobile n'a pour l'instant qu'un **écran d'accueil**
  fonctionnel ; le reste de chaque maquette HTML reste à reproduire en Flutter.
- Le backend n'est **pas encore déployé** sur NindoHost.
- Trois intégrations restent à brancher : l'envoi push réel (FCM), l'appel
  effectif à CinetPay, et l'export Excel/PDF des statistiques.

## Prochaines étapes possibles

- Déployer la base et l'API sur NindoHost pour avoir un environnement de test réel.
- Étoffer une interface mobile au-delà de son écran d'accueil.
- Mettre en place un build automatique (Codemagic ou GitHub Actions) pour
  obtenir un `.apk` installable sans matériel local.
