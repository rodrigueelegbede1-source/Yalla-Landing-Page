# Yalla — Application mobile (Flutter)

Squelette d'application connecté à `yalla-backend-api` (NestJS), qui aiguille
vers l'une des 5 interfaces déjà maquettées en HTML selon le rôle renvoyé par
la connexion.

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
    administrateur/ Accueil Administrateur (ruptures ouvertes, réseau)
    fabricant/       Accueil Fabricant (ruptures sur son catalogue uniquement)
    livreur/         Accueil Livreur (ruptures proches + envoi de position réelle)
    point_de_vente/  Accueil Point de vente (signalement de rupture)
    agent_recenseur/ Accueil Agent recenseur (formulaire + capture GPS réelle)
```

## Ce que ce squelette couvre déjà

- **Authentification réelle** contre `POST /auth/login`, token stocké de
  façon sécurisée, session restaurée au redémarrage de l'app.
- **Aiguillage par rôle** vers l'une des 5 interfaces (`main.dart`).
- **Appels API réels**, pas de données simulées : ruptures ouvertes
  (Administrateur), ruptures filtrées par fabricant, ruptures triées par
  proximité PostGIS (Livreur), signalement de rupture (Point de vente),
  création de point de vente avec GPS réel (Agent recenseur).
- **Position GPS réelle** envoyée par le livreur toutes les 10 secondes
  (`geolocator`), conforme à la fréquence recommandée dans
  `Yalla_Stack_Technique.md`.
- **Client WebSocket** prêt à consommer les événements `livreur:position` et
  `reseau:activite` de la passerelle temps réel du backend.

## Décision prise sur l'ID métier

Le token JWT porte désormais `idMetier` (fabricantId / livreurId /
pointDeVenteId / agentRecenseurId selon le rôle) en plus de l'ID utilisateur,
renvoyé directement par `POST /auth/login` — voir `auth_providers.dart`. Ça a
nécessité une migration supplémentaire côté base
(`010_utilisateur_point_de_vente.sql`) : `points_de_vente` n'avait pas de lien
vers un compte de connexion dans le schéma initial, contrairement aux autres
rôles.

## Ce qui reste à construire

- Le reste de chaque interface au-delà de l'écran d'accueil (les 4 autres
  onglets de chaque maquette HTML : Réseau, Statistiques, Notifications,
  Catalogue pour l'Administrateur ; Catalogue et Livreurs pour le Fabricant ;
  Historique et Profil pour le Livreur ; etc.) — chaque écran déjà construit
  ici sert de modèle pour brancher les autres sur l'API réelle.
- **Cartes réelles** (`google_maps_flutter` déjà en dépendance) — les écrans
  actuels affichent des listes, pas encore de carte interactive.
- **Notifications push** (Firebase déjà en dépendance, configuration
  `google-services.json` / `GoogleService-Info.plist` à ajouter).
- **Exécution non vérifiée** — comme pour le schéma SQL et le backend, cet
  environnement n'a pas d'accès réseau pour `flutter pub get` ni pour
  compiler l'app ; le code a été relu attentivement mais son premier
  démarrage réel se fera de votre côté.
