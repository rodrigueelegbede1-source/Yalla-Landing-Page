import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_providers.dart';

/// Reprend l'onglet Accueil de la maquette Fabricant : ruptures ouvertes sur
/// son propre catalogue uniquement (GET /ruptures/fabricant/:id, déjà filtré
/// côté API — voir RupturesService.findOuvertesParFabricant).
class FabricantHomeScreen extends ConsumerWidget {
  const FabricantHomeScreen({super.key, required this.fabricantId});

  final String fabricantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiClientProvider);
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(session.nom ?? 'Fabricant'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(sessionProvider.notifier).deconnecter(),
          ),
        ],
      ),
      body: FutureBuilder(
        future: api.dio.get('/ruptures/fabricant/$fabricantId'),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final ruptures = snapshot.data!.data as List;
          if (ruptures.isEmpty) {
            return const Center(child: Text('Aucune rupture ouverte sur votre catalogue.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: ruptures.length,
            itemBuilder: (context, i) {
              final r = ruptures[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline, color: Colors.orange),
                  title: Text(r['produit_nom'] ?? ''),
                  subtitle: Text('${r['point_de_vente_nom']} — ${r['commune']}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
