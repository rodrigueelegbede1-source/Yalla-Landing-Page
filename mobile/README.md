# Yalla — Application mobile (Flutter)

Application Android de terrain pour les revendeurs, distributeurs, livreurs et
agents recenseurs. Le revendeur utilise le catalogue digital pour envoyer une
demande de réapprovisionnement, suivre son état, recevoir les communications
du réseau et transmettre ses retours. Les ventes et stocks de boutique ne font
pas partie du parcours actuel.

Fabricants et administrateurs utilisent leurs consoles web sur `yalla.ci`.
Le distributeur dispose également d'une console web, et garde dans l'application
ses parcours terrain de flotte et de réseau.

## Démarrage

```bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=<URL_SUPABASE> \
  --dart-define=SUPABASE_ANON_KEY=<CLE_PUBLIQUE_SUPABASE>
```

Les valeurs Supabase sont fournies à la compilation. Ne placez jamais la clé
de service dans l'application : seule la clé publique anon y est utilisée et
les accès sont contrôlés par RLS.

## Organisation

```
lib/
  core/
    auth/          Session Supabase — connexion, déconnexion et rôle signé
    realtime/      Abonnements Supabase Realtime
  features/
    auth/           Écran de connexion
    administrateur/ Ancien écran mobile, non routé : console web
    fabricant/       Ancien écran mobile, non routé : console web
    distributeur/    Aperçu, demandes, retours, flotte et réseau
    livreur/         Courses, suivi de position et historique des livraisons
    point_de_vente/  Catalogue, demandes, messages et retours terrain
    agent_recenseur/ Inscription GPS des revendeurs et distributeurs
```

## Ce que ce squelette couvre déjà

- **Authentification Supabase** par téléphone et mot de passe; le rôle du jeton
  détermine le parcours. Fabricant et administrateur sont aiguillés vers leur
  console web au lieu d'écrans mobiles redondants.
- **Données métier réelles**, filtrées par RLS : catalogue et demandes du
  revendeur, demandes et flotte du distributeur, courses proches du livreur,
  inscription GPS pour l'agent recenseur.
- **Position GPS réelle** envoyée par le livreur toutes les 10 secondes
  (`geolocator`), conforme à la fréquence recommandée dans
  `Yalla_Stack_Technique.md`.
- **Supabase Realtime** met à jour les listes métier pertinentes.
- **Fabricant** : aperçu graphique, taux de service, ruptures et catalogue à
  partir de vues filtrées par le fabricant connecté.
- **Administrateur** : synthèse réseau, couverture par commune, gestion des
  acteurs et anomalies opérationnelles, sans afficher les ventes des boutiques.
- **Distributeur** : aperçu de ses courses, sa flotte et ses boutiques, via les
  vues limitées à son propre réseau. Affiliés et indépendants utilisent le même
  parcours, conformément au modèle métier.
- **Point de vente** : catalogue digital, demandes manuelles, messages illustrés,
  enquêtes/sondages et retours liés à une marque ou au distributeur attribué.

## Limites actuelles

- Android uniquement; aucune version iOS n'est distribuée.
- Les cartes interactives et les notifications push ne sont pas encore actives.
- Le paiement du réapprovisionnement reste convenu entre les partenaires;
  l'application enregistre le montant reçu en espèces par le livreur.
- Les anciennes tables et widgets de caisse/stock ne sont pas routés dans les
  parcours courants; ils ne doivent pas être réintroduits sans décision produit.
