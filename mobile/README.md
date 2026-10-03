# Yalla — Application mobile (Flutter)

Application qui achemine vers l'interface correspondant au rôle connecté.
L'espace boutique est un catalogue digital avec signalements de rupture,
communications du réseau et retours terrain. La caisse n'est pas exposée dans
l'application ; les tables historiques de ventes et stocks sont conservées en base.

## Démarrage

```bash
flutter pub get
flutter run --dart-define=YALLA_API_URL=http://<IP_DE_VOTRE_API>:3000
```

Sur un émulateur Android, `10.0.2.2` (valeur par défaut dans `api_client.dart`)
pointe vers `localhost` de la machine hôte. Sur un téléphone physique ou iOS,
passer l'IP réelle de la machine qui fait tourner l'API via `--dart-define`.

## Organisation

```
lib/
  core/
    api/          Client HTTP (Dio) avec injection automatique du token JWT
    auth/          Session utilisateur (Riverpod) — connexion, déconnexion
    realtime/      Client WebSocket vers la RealtimeGateway du backend
    storage/        Stockage sécurisé du token (flutter_secure_storage)
  features/
    auth/           Écran de connexion
    administrateur/ Supervision, couverture par commune, acteurs et alertes
    fabricant/       Aperçu, catalogue et ruptures de son propre catalogue
    distributeur/    Aperçu, courses, flotte et réseau attribué
    livreur/         Accueil Livreur (ruptures proches + envoi de position réelle)
    point_de_vente/  Catalogue, signalements, messages et retours terrain
    agent_recenseur/ Accueil Agent recenseur (formulaire + capture GPS réelle)
```

## Ce que ce squelette couvre déjà

- **Authentification réelle** contre `POST /auth/login`, token stocké de
  façon sécurisée, session restaurée au redémarrage de l'app.
- **Aiguillage par rôle** vers l'une des 6 interfaces (`main.dart`).
- **Appels API réels**, pas de données simulées : ruptures ouvertes
  (Administrateur), ruptures filtrées par fabricant, ruptures triées par
  proximité PostGIS (Livreur), signalement de rupture (Point de vente),
  création de point de vente avec GPS réel (Agent recenseur).
- **Position GPS réelle** envoyée par le livreur toutes les 10 secondes
  (`geolocator`), conforme à la fréquence recommandée dans
  `Yalla_Stack_Technique.md`.
- **Client WebSocket** prêt à consommer les événements `livreur:position` et
  `reseau:activite` de la passerelle temps réel du backend.
- **Fabricant** : aperçu graphique, taux de service, ruptures et catalogue à
  partir de vues filtrées par le fabricant connecté.
- **Administrateur** : synthèse réseau, couverture par commune, gestion des
  acteurs et anomalies opérationnelles, sans afficher les ventes des boutiques.
- **Distributeur** : aperçu de ses courses, sa flotte et ses boutiques, via les
  vues limitées à son propre réseau. Affiliés et indépendants utilisent le même
  parcours, conformément au modèle métier.
- **Point de vente** : catalogue digital, demandes manuelles, messages illustrés,
  enquêtes/sondages et retours liés à une marque ou au distributeur attribué.

## Décision prise sur l'ID métier

Le token JWT porte désormais `idMetier` (fabricantId / livreurId /
pointDeVenteId / agentRecenseurId selon le rôle) en plus de l'ID utilisateur,
renvoyé directement par `POST /auth/login` — voir `auth_providers.dart`. Ça a
nécessité une migration supplémentaire côté base
(`010_utilisateur_point_de_vente.sql`) : `points_de_vente` n'avait pas de lien
vers un compte de connexion dans le schéma initial, contrairement aux autres
rôles.

## Ce qui reste à construire

- Les écrans métier restants des rôles terrain, notamment l'historique et le
  profil du livreur ainsi que les vues de suivi avancées du point de vente et de
  l'agent recenseur. Les écrans déjà présents restent le modèle pour les
  brancher sur les données réelles.
- **Cartes réelles** (`google_maps_flutter` déjà en dépendance) — les écrans
  actuels affichent des listes, pas encore de carte interactive.
- **Notifications push** (Firebase déjà en dépendance, configuration
  `google-services.json` / `GoogleService-Info.plist` à ajouter).
- **Exécution non vérifiée** — comme pour le schéma SQL et le backend, cet
  environnement n'a pas d'accès réseau pour `flutter pub get` ni pour
  compiler l'app ; le code a été relu attentivement mais son premier
  démarrage réel se fera de votre côté.
