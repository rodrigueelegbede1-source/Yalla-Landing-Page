import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/supabase.dart';
import 'courses_tab.dart';
import 'livraison_tab.dart';

/// Interface du livreur : les courses disponibles, et celles qu'il a prises.
///
/// La position est remontée toutes les dix secondes tant que l'application est
/// ouverte. Le suivi en arrière-plan, qui exige un service de premier plan
/// Android et la gestion des restrictions de batterie, reste à faire : c'est le
/// point dur identifié au plan, volontairement laissé de côté pour l'instant.
/// En attendant, un livreur qui met son téléphone en poche cesse d'être suivi,
/// et il faut le savoir avant de promettre un suivi type Uber à un fabricant.
class LivreurHomeScreen extends ConsumerStatefulWidget {
  const LivreurHomeScreen({super.key, required this.livreurId});

  final String livreurId;

  @override
  ConsumerState<LivreurHomeScreen> createState() => _LivreurHomeScreenState();
}

class _LivreurHomeScreenState extends ConsumerState<LivreurHomeScreen> {
  Timer? _timerPosition;
  int _onglet = 0;
  bool _positionAutorisee = true;

  /// Incrémentées pour forcer le rechargement croisé des deux onglets : une
  /// course prise disparaît de la première liste et apparaît dans la seconde,
  /// une course abandonnée fait le trajet inverse.
  int _cleCourses = 0;
  int _cleLivraisons = 0;

  @override
  void initState() {
    super.initState();
    _demarrerSuiviPosition();
  }

  @override
  void dispose() {
    _timerPosition?.cancel();
    super.dispose();
  }

  Future<void> _demarrerSuiviPosition() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    final autorisee = permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;

    if (mounted) setState(() => _positionAutorisee = autorisee);
    if (!autorisee) return;

    await _envoyerPosition();
    _timerPosition = Timer.periodic(const Duration(seconds: 10), (_) => _envoyerPosition());
  }

  Future<void> _envoyerPosition() async {
    try {
      final p = await Geolocator.getCurrentPosition();
      // La position courante de `livreurs` est dénormalisée par un trigger :
      // on écrit uniquement l'historique, la base synchronise le reste.
      await supabase.from('positions_livreurs').insert({
        'livreur_id': widget.livreurId,
        'position': 'SRID=4326;POINT(${p.longitude} ${p.latitude})',
      });
    } catch (_) {
      // Une position perdue n'est pas un incident : la suivante arrive dans
      // dix secondes. On ne dérange pas le livreur avec un message pour autant.
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(session?.nom ?? 'Livreur'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Se déconnecter',
            onPressed: () => ref.read(authProvider).deconnecter(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_positionAutorisee)
            const MaterialBanner(
              content: Text(
                'Sans votre position, les courses ne peuvent pas être triées par distance.',
              ),
              leading: Icon(Icons.location_off_outlined),
              actions: <Widget>[
                TextButton(
                  onPressed: Geolocator.openAppSettings,
                  child: Text('Autoriser'),
                ),
              ],
            ),
          Expanded(
            child: IndexedStack(
              index: _onglet,
              children: [
                CoursesTab(
                  cle: _cleCourses,
                  onCoursePrise: () => setState(() => _cleLivraisons++),
                ),
                LivraisonTab(
                  cle: _cleLivraisons,
                  onChangement: () => setState(() => _cleCourses++),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _onglet,
        onDestinationSelected: (i) => setState(() => _onglet = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.near_me_outlined),
            selectedIcon: Icon(Icons.near_me),
            label: 'À proximité',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping),
            label: 'Mes courses',
          ),
        ],
      ),
    );
  }
}
