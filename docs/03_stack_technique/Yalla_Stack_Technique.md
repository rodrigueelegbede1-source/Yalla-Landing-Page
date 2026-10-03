# Stack technique proposée — Application Yalla

Recommandation construite à partir des contraintes du cahier des charges : app iOS + Android, géolocalisation temps réel type Uber, notifications de rupture, caisse enregistreuse type Loyverse, paiement mobile ivoirien, lancement sur Abidjan.

> **Mise à jour produit (2026-10-02)** : ce document conserve les choix historiques de stack, mais la caisse enregistreuse et le stock boutique sont retirés du parcours mobile. L'interface boutique est un catalogue digital avec signalements manuels, publicités illustrées, notifications, sondages et retours terrain. Voir `docs/HISTORIQUE.md` pour la décision et ses conséquences.

---

## 1. Résumé

| Brique | Choix recommandé | Alternative sérieuse |
|---|---|---|
| Application mobile | **Flutter** (Dart) | React Native |
| Backend / API | **NestJS** (Node.js, TypeScript) | Django (Python) |
| Base de données | **PostgreSQL + PostGIS** | MySQL + géo-index |
| Temps réel (positions, flux admin) | **Socket.io** (WebSockets) sur le backend NestJS | Firebase Realtime Database |
| Notifications push | **Firebase Cloud Messaging (FCM)** | OneSignal |
| Cartographie | **Google Maps SDK** | Mapbox |
| Paiement mobile | **CinetPay** | — |
| Stockage fichiers/images | **S3-compatible** (AWS S3 ou équivalent) | — |
| Authentification | **JWT + refresh token** | — |
| Hébergement | **NindoHost** | — |

---

## 2. Application mobile — Flutter

**Pourquoi** : un seul code source pour iOS et Android (exigence explicite du cahier des charges), bonnes performances sur du matériel d'entrée de gamme — pertinent pour un déploiement à Abidjan où le parc Android est très majoritaire et varié. Écosystème mature pour la géolocalisation temps réel et les cartes.

**Pourquoi pas React Native** : reste une alternative crédible et tout aussi viable (grande communauté, JavaScript/TypeScript partagé avec un backend Node). Flutter a un léger avantage sur la fluidité des animations et la cohérence visuelle entre iOS et Android, ce qui compte pour les 5 interfaces très différentes du projet.

**Point d'attention — dépendance au réseau** : le mode hors-ligne a été retiré du périmètre. L'application suppose une connexion active. Le corollaire est qu'il faut soigner le comportement en réseau faible — délais d'attente courts, messages d'erreur explicites, reprise manuelle — plutôt que de masquer la coupure.

---

## 3. Backend — NestJS (Node.js, TypeScript)

**Pourquoi** : structure imposée (modules, contrôleurs, services) qui convient bien à un projet avec 5 rôles et des permissions différenciées par interface. TypeScript partagé avec le front si un panneau web est ajouté plus tard (ex. back-office Administrateur en version web). Bon support natif de WebSockets pour le flux temps réel (positions des livreurs, notifications).

**Pourquoi pas Django** : très solide aussi, avec un excellent admin auto-généré qui pourrait accélérer la V1 de l'interface Administrateur. Le compromis : Django s'intègre moins naturellement avec du temps réel poussé (WebSockets moins central dans son écosystème) et le suivi de positions y est un peu plus de friction.

---

## 4. Base de données — PostgreSQL + PostGIS

**Pourquoi** : l'extension **PostGIS** est faite pour exactement ce cas d'usage — trouver les points de vente en rupture les plus proches d'un livreur, calculer des distances, filtrer par zone géographique (commune, ville). Le modèle de données déjà défini (`PointDeVente`, `PositionLivreur`, coordonnées lat/lng) s'y branche directement, avec des requêtes spatiales natives plutôt que des calculs de distance approximatifs en code applicatif.

---

## 5. Temps réel — Socket.io

**Pourquoi** : les positions des livreurs et le flux d'activité de la console Administrateur (déjà maquettés) ont besoin de pousser des mises à jour vers l'app sans que le client interroge le serveur en boucle. Socket.io s'intègre proprement dans NestJS et reste sous contrôle total (hébergement, coûts, données) plutôt que dépendant d'un service tiers.

**Alternative** : Firebase Realtime Database simplifie le développement initial (rien à héberger) mais lie le projet à l'écosystème Google et devient coûteux à mesure que le nombre de livreurs et de mises à jour de position augmente — moins adapté sur la durée vu la fréquence déjà définie (10 s en course).

---

## 6. Notifications push — Firebase Cloud Messaging

**Pourquoi** : gratuit, standard de fait sur iOS et Android, s'intègre nativement à Flutter. Sert à la fois les notifications de rupture, les splash publicitaires et les sondages définis dans le cahier des charges.

---

## 7. Cartographie — Google Maps SDK

**Pourquoi** : couverture et précision fiables sur Abidjan, SDK Flutter officiel bien maintenu, expérience déjà familière pour les livreurs (proche de Google Maps qu'ils utilisent probablement déjà).

**Point d'attention** : facturé au volume d'appels une fois le quota gratuit dépassé — à surveiller avec le nombre de livreurs actifs et la fréquence de rafraîchissement de la carte. **Mapbox** est une alternative avec une tarification souvent plus avantageuse à volume élevé, à réévaluer si les coûts Google Maps deviennent significatifs.

---

## 8. Paiement mobile — CinetPay

**Pourquoi** : les 5 fournisseurs déjà identifiés (Orange CI, MTN CI, Wave, Moov, Djamo) auraient chacun leur propre API, leurs propres délais d'homologation marchand et leur propre logique de webhook. **CinetPay**, agrégateur ivoirien, permet d'intégrer une seule API qui couvre ces opérateurs, réduisant fortement le temps de développement et de maintenance.

**À vérifier au démarrage du développement** : confirmer que Djamo, plus récent que les opérateurs mobile money classiques, est bien couvert par CinetPay au moment de l'intégration — sinon prévoir une intégration directe complémentaire pour ce seul fournisseur.

---

## 9. Hébergement — NindoHost

Hébergeur retenu pour l'infrastructure (base de données, backend, stockage). Étant un hébergeur local, il vaut la peine de vérifier dès le démarrage du projet ses garanties de disponibilité (SLA), ses options de sauvegarde automatique, et s'il propose une extension PostGIS prête à l'emploi sur ses offres PostgreSQL managées — sinon prévoir l'installation manuelle de l'extension sur un serveur dédié.

---

## 10. Ce que cette stack permet de couvrir directement

- Suivi temps réel des livreurs et des ruptures (PostGIS + Socket.io)
- Un seul code mobile pour les 5 interfaces (Flutter), déjà cohérent avec les maquettes réalisées
- Export Excel/PDF des statistiques (librairies `exceljs` et `pdfkit` côté NestJS)
- Paiement mobile multi-opérateurs sans multiplier les intégrations

## 11. Ce qui reste à décider

- Confirmer la couverture de Djamo par CinetPay avant le début de l'intégration paiement.
- Vérifier les offres PostgreSQL/PostGIS et les garanties de disponibilité chez NindoHost.
