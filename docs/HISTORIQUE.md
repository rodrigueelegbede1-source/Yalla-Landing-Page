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
| `04_maquettes/` | 6 prototypes HTML cliquables, un par interface |
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

9. **Le distributeur entre dans le produit, et la rupture est enfin routée**
   (2026-09-15, migration `011_distributeurs_et_escalade.sql`).

   Le schéma des acteurs a fait apparaître un sixième rôle, absent du cahier
   des charges initial : le **distributeur**. Décision : une rupture part au
   distributeur, **qui agit**, et le fabricant la voit **en lecture** sur son
   seul catalogue. Les trois cas de terrain (distributeur affilié, distributeur
   indépendant, fabricant qui distribue lui-même) tiennent dans une seule table,
   le troisième étant modélisé par un distributeur `auto_distribution`. Aucun
   cas particulier ne subsiste dans le code, tout passe toujours par un
   distributeur.

   Trois trous du schéma initial ont été comblés au passage, et ils étaient
   bloquants :

   - **La rupture n'enregistrait aucun acteur.** Elle passait de `signalee` à
     `prise_en_charge` sans dire à qui elle avait été envoyée ni qui l'avait
     prise. Aucun délai n'était mesurable, donc aucune escalade n'était
     déclenchable. Ajout de `distributeur_id`, `livreur_id`,
     `date_prise_en_charge` et `escaladee_le`.
   - **`prendreEnCharge` laissait passer deux preneurs.** L'UPDATE n'avait
     aucune condition sur le statut courant : deux livreurs pouvaient partir sur
     la même course en croyant chacun l'avoir obtenue. Remplacé par un UPDATE
     conditionnel qui renvoie 409 au perdant.
   - **Il manquait un statut terminal.** Une rupture que personne ne prenait
     restait ouverte à vie, et le taux de service, qui est l'argument vendu au
     fabricant, n'était pas calculable. Ajout de `non_servie` et de la vue
     `v_taux_de_service_par_fabricant`.

   **Règle d'escalade retenue : cercles concentriques puis péremption.** Passé
   `delai_escalade()` (2 h), la rupture s'ouvre aux autres distributeurs qui
   portent le même fabricant dans la même commune. Passé `delai_peremption()`
   (24 h), elle est close en `non_servie`. L'élargissement ne franchit jamais
   la frontière de la marque : en Côte d'Ivoire la distribution est
   territoriale, et proposer une rupture à un distributeur qui ne travaille pas
   cette marque casserait un accord au lieu de rendre service.

   **Choix d'implémentation structurant : le routage est en SQL.** La rupture la
   plus importante du produit, celle que la caisse déclenche quand une vente
   vide un stock, est créée par un trigger de `006` et ne passe jamais par
   NestJS. La résolution du destinataire est donc elle aussi un trigger
   (`BEFORE INSERT` sur `ruptures`). Écrite dans le service, elle aurait
   couvert le signalement manuel et manqué le mécanisme central.

   Conséquence de schéma : `livreurs.fabricant_id` devient
   `livreurs.distributeur_id`. Un livreur n'a jamais été l'employé d'une
   marque, mais de celui qui distribue.

10. **La chaîne complète tourne pour la première fois** (2026-09-15).

   Jusqu'ici, tout le code de ce dépôt avait été écrit sans jamais être exécuté :
   aucune migration appliquée, aucun endpoint interrogé. Ce jalon est franchi.
   Base PostgreSQL 17 + PostGIS 3.6 provisionnée, **11 migrations appliquées**,
   seed chargé, **API démarrée et interrogée**.

   **Trois bugs sont sortis, qu'aucune relecture n'avait vus** et qu'aucun outil
   d'analyse statique ne pouvait voir :

   - **Le seed n'avait jamais pu fonctionner.** Cinq `INSERT INTO utilisateurs`
     omettaient `mot_de_passe_hash`, qui est NOT NULL. Il échouait au deuxième
     utilisateur.
   - **Toutes les routes protégées répondaient 401.** `JwtModule.register()` lit
     `process.env.JWT_SECRET` à l'évaluation du décorateur, avant que
     `ConfigModule.forRoot()` ait chargé le `.env` ; `JwtStrategy`, instanciée
     plus tard, lisait la vraie valeur. Signature et vérification utilisaient donc
     deux secrets différents. Corrigé par `registerAsync` + `ConfigService`.
   - **Le garde-fou de concurrence était muet.** Sur un `UPDATE ... RETURNING`,
     TypeORM renvoie `[lignes, nombreAffecté]` et non les lignes : le test
     `length === 0` n'était jamais vrai, et le second livreur recevait un 200
     avec un tableau vide au lieu d'un 409.

   Le troisième est le plus instructif : la logique SQL était juste, et la suite
   de tests SQL la validait déjà. C'est la couche TypeScript qui trahissait. Les
   deux niveaux devaient être testés.

   **Première suite de tests du dépôt** : `database/tests/test_escalade.sql`,
   10 cas, branchée sur `npm test`. Elle vérifie le routage automatique depuis la
   caisse, les deux cercles d'accès, la non-réescalade, la concurrence entre deux
   preneurs, la péremption et les trois cas de terrain du modèle. Elle tourne dans
   une transaction close par `ROLLBACK`, donc rejouable à l'infini.

   **Le piège `initdb` documenté dans AGENTS.md est confirmé** : l'installateur
   standard s'arrête sur la locale « French_Côte d'Ivoire.1252 ». Contournement
   qui marche sans toucher aux réglages Windows : `initdb --locale=C`.

   *Correction apportée le 21/09/2026 :* `--locale=C` ne suffit plus. `initdb`
   échoue en RESTAURANT l'ancienne locale, après avoir tout fait, parce que
   l'apostrophe courbe de « Côte d'Ivoire » ne survit pas à l'aller-retour.
   Le seul contournement observé qui marche : basculer
   `HKCU\Control Panel\International` sur `fr-FR` / `FRA`, créer le cluster
   depuis un processus neuf, puis restaurer `fr-CI` / `FRI` (les valeurs
   d'origine sont notées dans `.devtools/locale-origine.txt`). Le cluster
   jetable vit dans `.devtools/data`, port 55432, et n'est pas conservé.

11. **Le tableau de bord administrateur** (2026-09-21).

   Le sixième rôle avait des comptes et aucun écran. Or c'est lui qui débloque
   tous les autres : sans lui, les demandes d'inscription déposées depuis le
   site s'empilent dans une table que personne ne regarde, et un distributeur
   qui démarre ne voit aucune boutique, sa politique ne lui montrant que les
   communes où il opère déjà.

   Trois vues (`v_supervision_reseau`, `v_anomalies_reseau`,
   `v_supervision_boutiques` / `_distributeurs`), une fonction
   `attribuer_boutique_admin`, et la page `landing/administration.html`.

   **Ce que l'administrateur ne voit pas, et ne verra pas** : les ventes et le
   chiffre d'affaires d'une boutique. Les politiques `stocks_prives` et
   `ventes_privees` omettent délibérément `est_admin()`, et un test le vérifie.
   La promesse faite au boutiquier est ce qui lui fait accepter la caisse
   gratuite ; une promesse qui souffre une exception pour l'exploitant n'en est
   plus une.

   **Deux défauts silencieux sont sortis en vérifiant l'écran sur la
   production**, et aucun des deux n'aurait produit la moindre erreur :

   - **`creer_compte_metier` ne savait pas créer un fabricant.** Elle traitait
     quatre rôles sur cinq et laissait passer le cinquième en rendant
     `id_metier: null`, sans exception. Le compte se serait connecté, son jeton
     n'aurait porté aucun `id_metier`, et toutes ses vues auraient rendu zéro
     ligne. L'annulation prévue dans la fonction Edge ne se déclenche que sur
     erreur, et il n'y en avait pas. Corrigé, et doublé d'un garde-fou général :
     tout rôle qui ressort sans ligne métier fait désormais échouer la
     transaction.
   - **Un fabricant voyait la ligne de ses concurrents.**
     `v_tableau_de_bord_fabricant` part de `fabricants`, table lisible de tous
     parce que le boutiquier parcourt les catalogues, et n'ajoutait aucun
     filtre. Pire que la fuite : la page lit `lignes[0]`, donc avec deux
     fabricants en base elle affichait à chacun le tableau de bord du premier
     venu, nom d'entreprise compris. Le filtre est maintenant dans la vue, pas
     dans la page.

   **Le script de déploiement mentait aussi.** Son rechargement du cache de
   schéma PostgREST passait `psql "postgresql://…" -w -q -c "NOTIFY …"` ; or le
   `getopt` de PostgreSQL sous Windows ne réordonne pas les arguments et
   s'arrête au premier qui n'est pas une option. La notification n'est jamais
   partie, psql sortait avec le code 0, et le script annonçait « cache
   rechargé ». Les déploiements marchaient quand même, PostgREST rechargeant
   aussi sur événement DDL, mais la garde ne gardait rien.

## Où ça en est, honnêtement

- **La base, le backend et le routage ont maintenant tourné pour de vrai**
  (voir l'entrée 10). Ce qui suit reste vrai en revanche.
- La validation a eu lieu sur **PostgreSQL 17**, alors que la cible documentée
  est la 15, et sur un cluster jetable en **locale C** monté hors de
  `Program Files` faute de droits administrateur. Le comportement en locale
  française n'est donc pas testé.
- Le **mobile n'a toujours jamais été compilé** : le SDK Flutter est absent de
  l'environnement. L'écran Distributeur est écrit mais n'a jamais tourné.
- Les modules **caisse, notifications, livraisons et transactions** n'ont aucun
  endpoint testé. Seuls l'authentification et le parcours de rupture l'ont été.
- Le distributeur a désormais sa maquette (`maquettes/distributeur/`, 4 écrans :
  courses, réseau, flotte, marques) et son écran Flutter d'accueil, au même
  niveau que les cinq autres rôles. Sa maquette est la seule à montrer les deux
  cercles d'accès, ce qui en fait le support de démonstration de la règle
  d'escalade.
- Chaque interface mobile n'a pour l'instant qu'un **écran d'accueil**
  fonctionnel ; le reste de chaque maquette HTML reste à reproduire en Flutter.
- Le backend n'est **pas encore déployé** sur NindoHost.
- Trois intégrations restent à brancher : l'envoi push réel (FCM), l'appel
  effectif à CinetPay, et l'export Excel/PDF des statistiques.

## Prochaines étapes possibles

- **Rejouer la validation sur PostgreSQL 15**, la version cible, et en locale
  française, pour lever les deux réserves de l'entrée 10.
- Étendre la suite de tests aux modules non couverts : caisse, livraisons,
  notifications. Le modèle est posé, il ne reste qu'à l'étendre.
- Déployer la base et l'API sur NindoHost pour avoir un environnement de test réel.
- Porter l'écran Distributeur au-delà de son accueil, comme les cinq autres.
- Étoffer une interface mobile au-delà de son écran d'accueil.
- Mettre en place un build automatique (Codemagic ou GitHub Actions) pour
  obtenir un `.apk` installable sans matériel local.
