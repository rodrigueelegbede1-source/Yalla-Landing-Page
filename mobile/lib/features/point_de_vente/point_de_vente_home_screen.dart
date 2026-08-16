import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_providers.dart';

/// Reprend le bouton central de la maquette Point de vente : "Signaler une
/// rupture". Le catalogue complet par catégorie (écran de sélection du
/// produit) reste à construire sur le même modèle que FabricantHomeScreen —
/// GET /produits/catalogue-global est déjà prêt côté API.
class PointDeVenteHomeScreen extends ConsumerWidget {
  const PointDeVenteHomeScreen({super.key, required this.pointDeVenteId});

  final String pointDeVenteId;

  Future<void> _signaler(BuildContext context, WidgetRef ref, String produitId) async {
    await ref.read(apiClientProvider).dio.post('/ruptures/point-de-vente/$pointDeVenteId', data: {
      'produitId': produitId,
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rupture signalée au fabricant')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(session.nom ?? 'Point de vente'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(sessionProvider.notifier).deconnecter(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Un produit manque en rayon ?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.warning_amber),
              label: const Text('Signaler une rupture'),
              onPressed: () {
                // TODO : ouvrir l'écran de sélection du produit dans le catalogue
                // global (GET /produits/catalogue-global) avant d'appeler _signaler().
              },
            ),
          ],
        ),
      ),
    );
  }
}
