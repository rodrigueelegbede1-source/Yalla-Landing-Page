# Modèle de données — Application Yalla

Ce document décrit le modèle de données commun aux 5 interfaces (Administrateur, Fabricant, Livreur, Point de vente, Agent recenseur), à partir du cahier des charges et des maquettes déjà validées.

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

---

## 2. Détail des entités

### `Utilisateur`
Compte de base, commun aux 5 rôles.

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

### `Stock`
Niveau de stock d'un produit sur un point de vente donné — alimenté par le module caisse enregistreuse.

| Champ | Type | Description |
|---|---|---|
| `id` | UUID (PK) | |
| `point_de_vente_id` | UUID (FK) | |
| `produit_id` | UUID (FK) | |
| `quantite` | int | |
| `date_maj` | datetime | |

### `Vente`
Ticket de caisse enregistré sur un point de vente (type Loyverse).

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

**Déclenchement automatique d'une rupture** : à chaque `LigneVente` enregistrée, décrémenter `Stock.quantite` du produit correspondant. Si `Stock.quantite` atteint 0, créer automatiquement une `Rupture` avec `signalement_automatique = true` et `statut = signalee` — sans action du gérant du point de vente. Le signalement manuel (bouton "Signaler une rupture" de la maquette Point de vente) reste disponible en complément, pour les cas où le stock n'est pas suivi précisément par la caisse.

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
