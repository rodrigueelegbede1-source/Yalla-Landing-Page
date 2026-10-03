# Modèle de données — Application Yalla

Ce document décrit le modèle de données commun aux 6 interfaces (Administrateur, Fabricant, Distributeur, Livreur, Point de vente, Agent recenseur), à partir du cahier des charges et des maquettes déjà validées.

> **Le distributeur a été ajouté le 2026-09-15** par la migration `011`, après la rédaction de ce document. Il reçoit les ruptures et agit dessus, le fabricant les voit en lecture. Voir `docs/HISTORIQUE.md`, entrée 9, pour le détail du routage et de la règle d'escalade.

> **Portée actuelle (2026-10-02)** : la caisse est retirée de l'application boutique. Les entités `Vente`, `LigneVente` et `Stock` ci-dessous documentent le schéma historique et ne sont plus utilisées par le parcours boutique. Les ruptures sont signalées manuellement depuis le catalogue. Les retours terrain sont ajoutés par la migration `20261002001000_retours_terrain.sql`.

---

## 1. Vue d'ensemble des entités

| Entité | Rôle |
|---|---|
| `Utilisateur` | Compte de connexion, commun à tous les rôles |
| `PointDeVente` | Boutique, superette, kiosque ou maquis recensé sur le réseau |
| `Fabricant` | Marque/fournisseur qui distribue des produits |
| `Produit` | Article du catalogue d'un fabricant |
| `AttributionReseau` | Association entre un fabricant et les points de vente qui lui sont attribués |
| `Livreur` | Agent de livraison affilié à un fabricant |
| `AgentRecenseur` | Agent terrain qui enregistre les points de vente |
| `Rupture` | Signalement d'un produit manquant sur un point de vente |
| `Livraison` | Course effectuée par un livreur pour résoudre une rupture |
| `Transaction` | Paiement mobile lié à une livraison |
| `Notification` | Message, splash publicitaire ou sondage émis par l'administrateur ou un fabricant |
| `SondageReponse` | Réponse d'un point de vente à un sondage |
| `RetourTerrain` | Observation envoyée par une boutique au fabricant ou distributeur qui la dessert |

---

## 2. Détail des entités

### `Utilisateur`
Compte de base, commun aux 6 rôles.

| Champ | Type | Description |
|---|---|---|
| `id` | UUID (PK) | Identifiant unique |
| `nom` | string | Nom complet ou raison sociale |
| `telephone` | string | Identifiant de connexion principal |
| `email` | string, nullable | |
| `mot_de_passe_hash` | string | |
| `role` | enum | `administrateur`, `fabricant`, `livreur`, `point_de_vente`, `agent_recenseur` |
| `date_creation` | datetime | |
| `derniere_connexion` | datetime, nullable | |

Chaque rôle a une table associée (`Fabricant`, `Livreur`, etc.) reliée à `Utilisateur` par `utilisateur_id`, pour ne pas dupliquer les champs de connexion.

### `PointDeVente`

| Champ | Type | Description |
|---|---|---|
| `id` | UUID (PK) | |
| `nom` | string | |
| `type_activite` | enum | `superette`, `boutique`, `kiosque`, `restaurant_maquis` |
| `adresse` | string | |
| `commune` | string | |
| `ville` | string | Abidjan au lancement |
| `latitude` / `longitude` | decimal | Position géolocalisée |
| `gerant_nom` | string | |
| `telephone` | string | |
| `statut` | enum | `actif`, `en_attente_activation`, `retire` |
| `agent_recenseur_id` | UUID (FK → AgentRecenseur) | Qui l'a enregistré |
| `date_enregistrement` | datetime | |

### `Fabricant`

| Champ | Type | Description |
|---|---|---|
| `id` | UUID (PK) | |
| `utilisateur_id` | UUID (FK) | |
| `nom` | string | Ex. Ivoire Boissons |
| `statut` | enum | `actif`, `suspendu` |

### `Produit`

| Champ | Type | Description |
|---|---|---|
| `id` | UUID (PK) | |
| `fabricant_id` | UUID (FK → Fabricant) | |
| `nom` | string | |
| `reference` | string | |
| `categorie` | enum | `boissons`, `epicerie`, `hygiene`, `snacking` (extensible) |
| `image_url` | string, nullable | Utilisée pour l'affichage des ruptures |
| `disponible` | bool | Faux si en rupture sur l'ensemble du réseau |

### `AttributionReseau`
Table de liaison many-to-many entre `Fabricant` et `PointDeVente`, gérée par l'administrateur.

| Champ | Type | Description |
|---|---|---|
| `id` | UUID (PK) | |
| `fabricant_id` | UUID (FK) | |
| `point_de_vente_id` | UUID (FK) | |
| `date_attribution` | datetime | |

### `Livreur`

| Champ | Type | Description |
|---|---|---|
| `id` | UUID (PK) | |
| `utilisateur_id` | UUID (FK) | |
| `fabricant_id` | UUID (FK → Fabricant) | Fabricant d'affiliation |
| `en_ligne` | bool | |
| `position_latitude` / `position_longitude` | decimal | Dernière position connue (dénormalisée depuis `PositionLivreur`, pour affichage rapide sur la carte) |
| `date_derniere_position` | datetime | |

### `PositionLivreur`
Historique des positions, horodaté — alimente le suivi temps réel façon Uber, le calcul des trajets et les statistiques de distance parcourue (déjà utilisées dans la maquette Livreur).

| Champ | Type | Description |
|---|---|---|
| `id` | UUID (PK) | |
| `livreur_id` | UUID (FK) | |
| `latitude` / `longitude` | decimal | |
| `horodatage` | datetime | |

En production, cette table grossit vite — prévoir une purge ou un archivage au-delà d'une fenêtre glissante (ex. 30 jours), la position courante restant dénormalisée sur `Livreur` pour les lectures fréquentes.

### `AgentRecenseur`

| Champ | Type | Description |
|---|---|---|
| `id` | UUID (PK) | |
| `utilisateur_id` | UUID (FK) | |
| `secteur` | string | Zone géographique couverte |

### `Rupture`

| Champ | Type | Description |
|---|---|---|
| `id` | UUID (PK) | |
| `point_de_vente_id` | UUID (FK) | |
| `produit_id` | UUID (FK) | |
| `quantite_demandee` | int, nullable | |
| `statut` | enum | `signalee`, `prise_en_charge`, `resolue` |
| `date_signalement` | datetime | |
| `date_resolution` | datetime, nullable | |
| `signalement_automatique` | bool | Vrai si détectée automatiquement plutôt que déclarée manuellement |

Le `fabricant_id` concerné se déduit de `produit.fabricant_id` — pas besoin de le dupliquer.

### `Livraison`

| Champ | Type | Description |
|---|---|---|
| `id` | UUID (PK) | |
| `rupture_id` | UUID (FK, nullable) | Rupture à l'origine de la livraison, si applicable |
| `livreur_id` | UUID (FK) | |
| `point_de_vente_id` | UUID (FK) | |
| `statut` | enum | `en_cours`, `terminee`, `annulee` |
| `date_debut` | datetime | |
| `date_fin` | datetime, nullable | |
| `montant` | decimal | Montant de la course, sert au calcul du CA |

### `Transaction`

| Champ | Type | Description |
|---|---|---|
| `id` | UUID (PK) | |
| `livraison_id` | UUID (FK) | |
| `montant` | decimal | |
| `fournisseur` | enum | `orange_ci`, `mtn_ci`, `wave`, `moov`, `djamo` |
| `statut` | enum | `en_attente`, `confirmee`, `echouee` |
| `date` | datetime | |

### `Notification`

| Champ | Type | Description |
|---|---|---|
| `id` | UUID (PK) | |
| `emetteur_id` | UUID (FK → Utilisateur) | Administrateur ou fabricant |
| `type` | enum | `notification`, `splash_publicitaire`, `sondage` |
| `titre` | string | |
| `message` | text | |
| `cible` | enum | `reseau_complet`, `fabricants`, `points_de_vente`, `livreurs` |
| `date_envoi` | datetime | |

### `SondageReponse`
Une notification de type `sondage` porte ses options ; chaque réponse d'un point de vente est enregistrée séparément.

| Champ | Type | Description |
|---|---|---|
| `id` | UUID (PK) | |
| `notification_id` | UUID (FK) | |
| `point_de_vente_id` | UUID (FK) | |
| `option_choisie` | string | |
| `date_reponse` | datetime | |

### `RetourTerrain`
Observation envoyée par une boutique à un fabricant ou au distributeur qui dessert cette boutique.

| Champ | Type | Description |
|---|---|---|
| `id` | UUID (PK) | |
| `point_de_vente_id` | UUID (FK) | Boutique émettrice |
| `destinataire_role` | enum texte | `fabricant` ou `distributeur` |
| `fabricant_id` | UUID (FK, nullable) | Renseigné si le retour vise une marque |
| `distributeur_id` | UUID (FK, nullable) | Renseigné si le retour vise le distributeur attribué |
| `produit_id` | UUID (FK, nullable) | Produit concerné, facultatif pour un retour au distributeur |
| `sujet` | enum texte | `qualite`, `prix`, `disponibilite`, `livraison`, `publicite`, `autre` |
| `message` | texte | 5 à 1200 caractères |
| `created_at` | timestamptz | Date d'envoi |

La RPC déduit la boutique depuis le jeton et vérifie les attributions avant
l'envoi. RLS rend le retour visible à la boutique émettrice et au seul
destinataire désigné.

### `Stock` (historique, hors parcours boutique actuel)
Niveau de stock historique d'un produit sur un point de vente donné.

| Champ | Type | Description |
|---|---|---|
| `id` | UUID (PK) | |
| `point_de_vente_id` | UUID (FK) | |
| `produit_id` | UUID (FK) | |
| `quantite` | int | |
| `date_maj` | datetime | |

### `Vente` et `LigneVente` (historique, hors parcours boutique actuel)
Anciennes lignes de caisse conservées pour préserver les données existantes.

| Champ | Type | Description |
|---|---|---|
| `id` | UUID (PK) | |
| `point_de_vente_id` | UUID (FK) | |
| `date_vente` | datetime | |
| `montant_total` | decimal | |

### `LigneVente`

| Champ | Type | Description |
|---|---|---|
| `id` | UUID (PK) | |
| `vente_id` | UUID (FK) | |
| `produit_id` | UUID (FK) | |
| `quantite` | int | |
| `prix_unitaire` | decimal | |

**Ancien déclenchement de rupture (historique, hors parcours mobile actuel)** : le trigger de caisse de la migration `006` peut créer une rupture à partir d'une `LigneVente` qui vide le stock. Cette chaîne et ses données sont conservées, mais la boutique ne tient plus de caisse ni d'inventaire dans Yalla. Le parcours actif est le signalement manuel depuis le catalogue digital.

---

## 3. Règles métier issues du cahier des charges

- Un **fabricant** ne voit que les ruptures et statistiques liées à **son propre catalogue** — filtrer systématiquement par `produit.fabricant_id`.
- Un **livreur** n'est affilié qu'à **un seul fabricant** à la fois (`Livreur.fabricant_id`), et ne reçoit que les ruptures de ce fabricant.
- Un **point de vente** peut être attribué à **plusieurs fabricants** (`AttributionReseau`), et accède au catalogue global tous fabricants confondus.
- L'**administrateur** a une visibilité totale sur toutes les tables, sans filtre.
- Un point de vente créé par un **agent recenseur** reste au statut `en_attente_activation` jusqu'à validation par l'administrateur (cf. maquette Administrateur → activation des interfaces).
- Le **chiffre d'affaires** affiché dans les tableaux de bord se calcule à partir de la somme des `Livraison.montant` (ou des `Transaction` confirmées), filtré par fabricant, livreur ou point de vente selon la vue.

---

## 4. Points à trancher avant le développement

- ~~Fréquence de mise à jour de `PositionLivreur`~~ — tranché : 10 s (ou 25-30 m parcourus, selon la première condition atteinte) en course active, 1 fois par minute à l'arrêt, aucune remontée hors ligne. Voir section 5.
- ~~Produits hors catalogue Yalla~~ — tranché : un point de vente peut vendre des produits hors catalogue. Voir `Stock.produit_id` en section 5.

---

## 5. Compléments suite aux dernières décisions

### Fréquence de `PositionLivreur`
- **En course, en mouvement** : une ligne toutes les 10 secondes, ou tous les 25-30 mètres parcourus — la première condition atteinte déclenche l'écriture.
- **En ligne, immobile** (arrêt à un point de vente) : 1 ligne par minute tant que le déplacement reste sous quelques mètres.
- **Hors ligne** : aucune écriture.
- Volumétrie indicative : environ 86 000 lignes/jour pour 30 livreurs actifs sur 8 h — cohérente avec l'archivage à 30 jours déjà prévu.

### Produits hors catalogue
Un point de vente peut vendre des produits qui ne figurent dans le catalogue d'aucun fabricant du réseau Yalla. Conséquences sur le modèle :

- `Stock.produit_id` devient **nullable**, ou `Stock` gagne un champ `produit_libre_nom` (string) utilisé quand l'article ne correspond à aucun `Produit` du catalogue.
- Ces ventes hors catalogue **n'alimentent aucune `Rupture` ni aucun fabricant** — le déclenchement automatique de rupture (section 3) ne s'applique qu'aux lignes de vente liées à un `Produit` du catalogue.
- Elles comptent normalement dans `Vente.montant_total` et donc dans le chiffre d'affaires du point de vente, mais pas dans le CA par fabricant.
