import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../../core/auth/auth_providers.dart';

/// Reprend l'écran "Carte" de la maquette Livreur : liste des ruptures les
/// plus proches (GET /ruptures/proximite, tri PostGIS), et envoi périodique de
/// la position réelle du téléphone vers POST /livreurs/position — fréquence
/// alignée sur la recommandation de Yalla_Stack_Technique.md (10 s en course
/// active).
///
/// L'identifiant du livreur n'est plus passé dans l'URL : le backend le lit
/// dans le token. `livreurId` reste utile à l'écran lui-même, pas à l'appel.
class LivreurHomeScreen extends ConsumerStatefulWidget {
  const LivreurHomeScreen({super.key, required this.livreurId});

  final String livreurId;

  @override
  ConsumerState<LivreurHomeScreen> createState() => _LivreurHomeScreenState();
}

class _LivreurHomeScreenState extends ConsumerState<LivreurHomeScreen> {
  Timer? _timerPosition;

  @override
  void initState() {
    super.initState();
    _timerPosition = Timer.periodic(const Duration(seconds: 10), (_) => _envoyerPosition());
  }

  Future<void> _envoyerPosition() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
    final position = await Geolocator.getCurrentPosition();
    await ref.read(apiClientProvider).dio.post('/livreurs/position', data: {
      'latitude': position.latitude,
      'longitude': position.longitude,
    });
  }

  @override
  void dispose() {
    _timerPosition?.cancel();
    super.dispose();
  }

  // Sur un ConsumerState, 'ref' est deja un membre de la classe. L'ajouter en
  // parametre casse la signature heritee de State.build() et le fichier ne
  // compile pas.
  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiClientProvider);
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(session.nom ?? 'Livreur'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(sessionProvider.notifier).deconnecter(),
          ),
        ],
      ),
      body: FutureBuilder(
        future: api.dio.get('/ruptures/proximite'),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final ruptures = snapshot.data!.data as List;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: ruptures.length,
            itemBuilder: (context, i) {
              final r = ruptures[i];
              final distanceKm = (r['distance_metres'] as num) / 1000;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.local_shipping_outlined),
                  title: Text(r['produit_nom'] ?? ''),
                  subtitle: Text(r['point_de_vente_nom'] ?? ''),
                  trailing: Text('${distanceKm.toStringAsFixed(1)} km'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
