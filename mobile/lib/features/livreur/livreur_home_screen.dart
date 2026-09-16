import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/format.dart';
import '../../core/supabase.dart';

/// Écran du livreur : les courses qu'il peut prendre, triées par distance.
///
/// Le tri par proximité est calculé par PostGIS, pas en Dart : la fonction
/// `courses_a_proximite()` utilise l'opérateur de plus proche voisin et l'index
/// spatial. Trier côté client obligerait à télécharger tout le réseau.
///
/// La position est remontée toutes les 10 secondes pendant que l'écran est
/// ouvert. Le suivi en arrière-plan, qui exige un service de premier plan
/// Android et la gestion des restrictions de batterie, reste à faire : c'est le
/// point dur identifié au plan, volontairement laissé de côté pour l'instant.
class LivreurHomeScreen extends ConsumerStatefulWidget {
  const LivreurHomeScreen({super.key, required this.livreurId});

  final String livreurId;

  @override
  ConsumerState<LivreurHomeScreen> createState() => _LivreurHomeScreenState();
}

class _LivreurHomeScreenState extends ConsumerState<LivreurHomeScreen> {
  Timer? _timerPosition;
  late Future<List<Map<String, dynamic>>> _courses;
  bool _positionAutorisee = false;

  @override
  void initState() {
    super.initState();
    _courses = _charger();
    _demarrerSuiviPosition();
  }

  @override
  void dispose() {
    _timerPosition?.cancel();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _charger() async {
    final lignes = await supabase.rpc('courses_a_proximite', params: {'p_limite': 20});
    return List<Map<String, dynamic>>.from(lignes as List);
  }

  Future<void> _rafraichir() async {
    final f = _charger();
    setState(() => _courses = f);
    await f;
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
      // 10 secondes. On ne dérange pas le livreur avec un message pour autant.
    }
  }

  Future<void> _prendre(String ruptureId) async {
    try {
      await supabase.rpc('prendre_rupture', params: {'p_rupture_id': ruptureId});
      _message('Course prise. Bonne route.');
    } catch (e) {
      // Cas le plus fréquent et le plus important : un autre livreur a été plus
      // rapide. Le message vient de la base, il est déjà écrit pour être lu.
      _message(messageErreur(e));
    }
    await _rafraichir();
  }

  void _message(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texte)));
  }

  int _ancienneteSecondes(Object? dateIso) {
    final d = DateTime.tryParse(dateIso?.toString() ?? '');
    if (d == null) return 0;
    return DateTime.now().difference(d).inSeconds;
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
            child: RefreshIndicator(
              onRefresh: _rafraichir,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _courses,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return _Message(
                      icone: Icons.cloud_off_outlined,
                      titre: 'Chargement impossible',
                      texte: messageErreur(snap.error!),
                    );
                  }

                  final courses = snap.data ?? const [];
                  if (courses.isEmpty) {
                    return const _Message(
                      icone: Icons.check_circle_outline,
                      titre: 'Aucune course à proximité',
                      texte: 'Les ruptures de votre secteur apparaîtront ici dès '
                          'qu\'une boutique en signalera une.',
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: courses.length,
                    itemBuilder: (context, i) {
                      final c = courses[i];
                      final km = ((c['distance_metres'] as num?) ?? 0) / 1000;
                      final elargie = c['cercle'] == 'elargi';
                      final quantite = c['quantite_demandee'] as int?;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          leading: Icon(
                            elargie ? Icons.public : Icons.inventory_2_outlined,
                            color: elargie ? Colors.blueGrey : Colors.orange,
                          ),
                          title: Text(c['produit_nom'] as String? ?? ''),
                          subtitle: Text(
                            '${c['point_de_vente_nom']} · ${c['commune']}\n'
                            '${km.toStringAsFixed(1)} km'
                            '${quantite != null ? ' · $quantite carton(s)' : ''}'
                            ' · depuis ${depuis(_ancienneteSecondes(c['date_signalement']))}',
                            style: const TextStyle(height: 1.4),
                          ),
                          isThreeLine: true,
                          trailing: FilledButton(
                            onPressed: () => _prendre(c['rupture_id'] as String),
                            child: const Text('Prendre'),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icone, required this.titre, required this.texte});
  final IconData icone;
  final String titre;
  final String texte;

  @override
  Widget build(BuildContext context) => ListView(
        children: [
          const SizedBox(height: 80),
          Icon(icone, size: 56),
          const SizedBox(height: 20),
          Text(titre,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(texte,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, height: 1.5)),
          ),
        ],
      );
}
