import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/coque.dart';
import '../../core/theme.dart';
import '../../core/comptes.dart';
import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/widgets.dart';
import '../distributeur/flotte_tab.dart' show afficherIdentifiants, telephoneSaisiValide;
import 'inscription_distributeur.dart';

/// L'agent recenseur : inscrire une boutique, sur le pas de sa porte.
///
/// POURQUOI CE RÔLE REVIENT DANS LE PÉRIMÈTRE. Il en avait été écarté au plan,
/// et c'était une erreur de ma part : sans lui, chaque boutique du pilote
/// demandait deux `INSERT` SQL et un appel à l'API d'administration, tapés à la
/// main. Recenser dix boutiques à Cocody devenait un travail de développeur, ce
/// qui bloquait purement et simplement la phase de terrain.
///
/// L'écran est conçu pour être rempli debout, dans la rue, d'une seule main :
///
///   * la position est prise automatiquement, sans que l'agent ait à la saisir.
///     C'est elle qui décide ensuite de quel livreur est le plus proche, donc
///     elle doit être juste, et une saisie manuelle de coordonnées ne l'est
///     jamais ;
///   * le mot de passe est généré, lisible à voix haute, et affiché une seule
///     fois. Il n'est stocké en clair nulle part ;
///   * le formulaire tient en six champs. Tout le reste se corrige plus tard.
class AgentRecenseurHomeScreen extends ConsumerStatefulWidget {
  const AgentRecenseurHomeScreen({super.key, required this.agentId});

  final String agentId;

  @override
  ConsumerState<AgentRecenseurHomeScreen> createState() =>
      _AgentRecenseurHomeScreenState();
}

class _AgentRecenseurHomeScreenState
    extends ConsumerState<AgentRecenseurHomeScreen> {
  late Future<List<Map<String, dynamic>>> _recensements;

  @override
  void initState() {
    super.initState();
    _recensements = _charger();
  }

  Future<List<Map<String, dynamic>>> _charger() async {
    final lignes = await supabase
        .from('v_mes_recensements')
        .select()
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(lignes);
  }

  Future<void> _rafraichir() async {
    final f = _charger();
    if (mounted) setState(() => _recensements = f);
    await f;
  }

  Future<void> _recenser() async {
    final compte = await Navigator.of(context).push<CompteCree>(
      MaterialPageRoute(builder: (_) => const _FormulaireRecensement()),
    );
    if (compte == null || !mounted) return;

    await _rafraichir();
    if (!mounted) return;
    await afficherIdentifiants(context, compte, role: 'point_de_vente');
  }

  /// L'agent inscrit aussi les distributeurs.
  ///
  /// La base l'y autorisait depuis la migration de gestion du réseau ; seul
  /// l'écran manquait. Sur le terrain, l'agent rencontre les grossistes avant
  /// les boutiques : ce sont eux qui savent quelles échoppes existent. Le
  /// renvoyer vers le formulaire du site revenait à perdre la personne qu'on
  /// avait en face de soi.
  Future<void> _inscrireDistributeur() async {
    final compte = await Navigator.of(context).push<CompteCree>(
      MaterialPageRoute(builder: (_) => const InscriptionDistributeur()),
    );
    if (compte == null || !mounted) return;
    await afficherIdentifiants(context, compte, role: 'distributeur');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;

    // LA GRILLE DE TUILES TROUVE ICI SON RÔLE, et c'est le seul.
    //
    // Elle avait été écartée de l'écran du boutiquier, qui va directement au
    // catalogue digital et à ses messages : un écran d'accueil aurait ajouté
    // une tape à ses gestes quotidiens.
    //
    // L'agent est l'inverse exact. Il a deux gestes, occasionnels, et entre
    // les deux il consulte sa tournée. Deux tuiles pleine largeur se touchent
    // sans viser, avec une main, dans la rue — ce qu'un bouton flottant
    // unique ne permettait pas, puisqu'il n'offrait qu'une seule des deux
    // actions et cachait la seconde nulle part.
    return Scaffold(
      backgroundColor: Jetons.vert800,
      body: CoqueVerte(
        entete: SalutationCanevas(
          salutation: 'Bonjour,',
          nom: session?.nom ?? 'Recensement',
          detail: 'Chaque point de vente inscrit entre dans le réseau.',
          actions: [
            BoutonCanevas(
              icone: Icons.logout,
              infobulle: 'Se déconnecter',
              onTap: () => ref.read(authProvider).deconnecter(),
            ),
          ],
        ),
        enfant: RefreshIndicator(
        onRefresh: _rafraichir,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _recensements,
          builder: (context, snap) {
            final liste = snap.data ?? const [];

            // Compte du jour : l'agent est payé au recensement, il doit pouvoir
            // vérifier son chiffre sans appeler personne.
            final aujourdhui = DateTime.now();
            final duJour = liste.where((b) {
              final d = DateTime.tryParse(b['created_at']?.toString() ?? '');
              return d != null &&
                  d.year == aujourdhui.year &&
                  d.month == aujourdhui.month &&
                  d.day == aujourdhui.day;
            }).length;

            // LES DEUX TUILES RESTENT VISIBLES QUEL QUE SOIT L'ÉTAT DE LA
            // LISTE, y compris pendant le chargement et en cas d'erreur
            // réseau. L'agent est dans la rue avec quelqu'un en face de lui :
            // une liste qui n'a pas pu se charger ne doit pas l'empêcher
            // d'inscrire une boutique, puisque l'inscription ne dépend pas de
            // cette lecture.
            final actions = GrilleActions(tuiles: [
              TuileAction(
                icone: Icons.add_business,
                libelle: 'Recenser un revendeur',
                onTap: _recenser,
              ),
              TuileAction(
                icone: Icons.local_shipping_outlined,
                libelle: 'Inscrire un distributeur',
                teinte: Jetons.vert500,
                onTap: _inscrireDistributeur,
              ),
            ]);

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                actions,
                const SizedBox(height: 22),

                if (snap.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snap.hasError)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Jetons.alerte.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(Jetons.rCarte),
                    ),
                    child: Text(messageErreur(context, snap.error!),
                        style: const TextStyle(fontSize: 13.5, height: 1.45)),
                  )
                else if (liste.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Jetons.blanc,
                      borderRadius: BorderRadius.circular(Jetons.rCarte),
                      boxShadow: Jetons.ombreCarte,
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.storefront_outlined,
                            size: 40, color: Jetons.vert700),
                        SizedBox(height: 12),
                        Text('Aucun revendeur recensé',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        SizedBox(height: 8),
                        Text(
                          'Chaque revendeur inscrit accède au catalogue digital '
                          'et peut signaler ses besoins. Commencez par ceux de '
                          'votre secteur.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13.5, height: 1.45),
                        ),
                      ],
                    ),
                  )
                else ...[
                  TitreSection('Ma tournée',
                      detail: '$duJour aujourd\'hui · ${liste.length} au total'),
                  ...liste.map((b) => Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const Icon(Icons.storefront_outlined),
                        title: Text(b['nom'] as String? ?? '',
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${b['commune']} · ${b['type_activite']}\n'
                          '${b['gerant_nom'] ?? ''} · ${b['telephone'] ?? ''}',
                          style: const TextStyle(fontSize: 12, height: 1.4),
                        ),
                        isThreeLine: true,
                        trailing: Etiquette(
                          texte: (b['statut'] as String? ?? '').toUpperCase(),
                          couleur:
                              b['statut'] == 'actif' ? Colors.green : Colors.orange,
                        ),
                      ),
                    )),
                ],
              ],
            );
          },
        ),
        ),
      ),
    );
  }
}

class _FormulaireRecensement extends StatefulWidget {
  const _FormulaireRecensement();

  @override
  State<_FormulaireRecensement> createState() => _FormulaireRecensementState();
}

class _FormulaireRecensementState extends State<_FormulaireRecensement> {
  final _cleForm = GlobalKey<FormState>();
  final _nomBoutique = TextEditingController();
  final _nomGerant = TextEditingController();
  final _telephone = TextEditingController();
  final _commune = TextEditingController();
  final _adresse = TextEditingController();

  String _typeActivite = 'boutique';
  late String _motDePasse = ServiceComptes.motDePasseLisible();

  Position? _position;
  bool _localisation = false;
  String? _erreurPosition;
  bool _envoi = false;
  String? _erreur;

  static const _types = {
    'boutique': 'Boutique',
    'superette': 'Supérette',
    'kiosque': 'Kiosque',
    'restaurant_maquis': 'Restaurant ou maquis',
  };

  @override
  void initState() {
    super.initState();
    _localiser();
  }

  @override
  void dispose() {
    _nomBoutique.dispose();
    _nomGerant.dispose();
    _telephone.dispose();
    _commune.dispose();
    _adresse.dispose();
    super.dispose();
  }

  /// La position de la boutique, c'est-à-dire celle de l'agent qui se tient
  /// devant elle. C'est la donnée la plus importante du recensement : elle
  /// décide ensuite de quel livreur est le plus proche.
  Future<void> _localiser() async {
    setState(() {
      _localisation = true;
      _erreurPosition = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'La localisation du téléphone est désactivée.';
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw 'Sans la position, la boutique ne peut pas être recensée.';
      }

      // LE DÉLAI N'EST PAS UNE PRÉCAUTION DE CONFORT. Sans lui,
      // `getCurrentPosition` attend indéfiniment quand le GPS n'accroche pas :
      // à l'intérieur d'une boutique d'Adjamé, entre deux immeubles du Plateau,
      // l'agent reste bloqué sur « Relevé en cours » sans aucune sortie, et
      // Android finit par déclarer l'application ne répondant plus. Constaté au
      // premier essai réel.
      Position? p;
      try {
        p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20),
          ),
        );
      } on TimeoutException {
        // Repli sur la dernière position connue. Elle date peut-être de la
        // boutique précédente, d'où la précision affichée et le bouton
        // « Reprendre » : c'est à l'agent de juger, pas au code de décider à sa
        // place. Mieux vaut une position approximative qu'aucun recensement.
        p = await Geolocator.getLastKnownPosition();
        if (p == null) {
          throw 'Le GPS n\'accroche pas ici. Sortez devant la boutique, '
              'puis reprenez le relevé.';
        }
      }

      if (!mounted) return;
      setState(() {
        _position = p;
        _localisation = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _localisation = false;
        _erreurPosition = e is String ? e : _lisible(e);
      });
    }
  }

  /// Les exceptions de `geolocator` sont en anglais et parlent de « location
  /// service ». L'agent lit du français, et doit savoir quoi faire.
  String _lisible(Object e) {
    final brut = e.toString();
    if (brut.contains('disabled') || brut.contains('LocationServiceDisabled')) {
      return 'La localisation du téléphone est éteinte. Activez-la dans les '
          'réglages, puis reprenez.';
    }
    if (brut.contains('denied') || brut.contains('Permission')) {
      return 'Yalla n\'a pas accès à votre position. Autorisez-la pour pouvoir '
          'recenser.';
    }
    return 'Impossible de relever la position. Sortez devant la boutique, '
        'puis reprenez.';
  }

  Future<void> _valider() async {
    if (!(_cleForm.currentState?.validate() ?? false)) return;

    final p = _position;
    if (p == null) {
      setState(() => _erreur =
          'La position n\'a pas encore été relevée. Elle est indispensable : '
          'c\'est elle qui décide du livreur le plus proche.');
      return;
    }

    setState(() {
      _envoi = true;
      _erreur = null;
    });

    try {
      final compte = await const ServiceComptes().creer(
        // Le compte appartient au gérant, pas à la boutique : c'est lui qui
        // consultera le catalogue et transmettra les besoins du point de vente.
        nom: _nomGerant.text,
        telephone: _telephone.text,
        role: 'point_de_vente',
        motDePasse: _motDePasse,
        details: {
          'nom_boutique': _nomBoutique.text.trim(),
          'type_activite': _typeActivite,
          'commune': _commune.text.trim(),
          'adresse': _adresse.text.trim(),
          'latitude': p.latitude,
          'longitude': p.longitude,
        },
      );
      if (!mounted) return;
      Navigator.pop(context, compte);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _erreur = messageCompte(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recenser une boutique')),
      body: Form(
        key: _cleForm,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _CartePosition(
              position: _position,
              enCours: _localisation,
              erreur: _erreurPosition,
              onReessayer: _localiser,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nomBoutique,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom de la boutique',
                hintText: 'Supérette Akwaba',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v ?? '').trim().length < 2 ? 'Nom trop court' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _typeActivite,
              decoration: const InputDecoration(
                labelText: 'Type d\'activité',
                border: OutlineInputBorder(),
              ),
              items: _types.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _typeActivite = v ?? 'boutique'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _commune,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Commune',
                hintText: 'Cocody',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v ?? '').trim().length < 3 ? 'Commune obligatoire' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _adresse,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Repère (facultatif)',
                hintText: 'Face à la pharmacie Saint-Jean',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Le gérant',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 4),
            const Text(
              'C\'est lui qui consultera le catalogue et signalera les produits manquants. Son numéro lui sert '
              'd\'identifiant.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nomGerant,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom du gérant',
                hintText: 'Aya Kouassi',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v ?? '').trim().length < 3 ? 'Nom trop court' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _telephone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              decoration: const InputDecoration(
                labelText: 'Téléphone',
                hintText: '07 06 30 30 30',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  telephoneSaisiValide(v) ? null : 'Numéro incomplet',
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Mot de passe à remettre',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'En générer un autre',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => setState(
                      () => _motDePasse = ServiceComptes.motDePasseLisible()),
                ),
              ),
              child: Text(_motDePasse,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 3)),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 16),
              Text(_erreur!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _envoi ? null : _valider,
              child: _envoi
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Inscrire la boutique'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

/// L'état de la position, avec sa précision.
///
/// La précision est affichée parce qu'elle change le sens de la donnée : à
/// cinquante mètres près, dans une rue d'Adjamé, on ne sait plus de quelle
/// boutique il s'agit. L'agent doit pouvoir décider d'attendre ou de ressayer.
class _CartePosition extends StatelessWidget {
  const _CartePosition({
    required this.position,
    required this.enCours,
    required this.erreur,
    required this.onReessayer,
  });

  final Position? position;
  final bool enCours;
  final String? erreur;
  final VoidCallback onReessayer;

  @override
  Widget build(BuildContext context) {
    if (enCours) {
      return const Card(
        child: ListTile(
          leading: SizedBox(
              height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)),
          title: Text('Relevé de la position en cours'),
          subtitle: Text('Restez devant la boutique.'),
        ),
      );
    }

    if (position == null) {
      return Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: ListTile(
          leading: const Icon(Icons.location_off_outlined),
          title: const Text('Position indisponible'),
          subtitle: Text(erreur ?? 'Impossible de relever la position.'),
          trailing: TextButton(onPressed: onReessayer, child: const Text('Réessayer')),
        ),
      );
    }

    final p = position!;
    final precise = p.accuracy <= 25;

    return Card(
      child: ListTile(
        leading: Icon(precise ? Icons.gps_fixed : Icons.gps_not_fixed,
            color: precise ? Colors.green : Colors.orange),
        title: Text('Position relevée à ${p.accuracy.round()} m près'),
        subtitle: Text(
          precise
              ? '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}'
              : 'Trop imprécis pour distinguer deux boutiques voisines. '
                  'Attendez quelques secondes puis reprenez.',
          style: const TextStyle(fontSize: 12, height: 1.35),
        ),
        trailing: TextButton(onPressed: onReessayer, child: const Text('Reprendre')),
      ),
    );
  }
}
