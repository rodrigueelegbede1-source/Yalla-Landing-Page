import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_providers.dart';

/// Point de départ de la console Administrateur — reprend la structure de
/// la maquette HTML (tableau de bord, réseau, statistiques, notifications,
/// catalogue). Ici : uniquement l'onglet Tableau de bord, câblé sur l'API
/// réelle (GET /ruptures), pour servir de modèle aux autres onglets.
class AdministrateurHomeScreen extends ConsumerWidget {
  const AdministrateurHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiClientProvider);
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Bonjour, ${session.nom ?? ''}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(sessionProvider.notifier).deconnecter(),
          ),
        ],
      ),
      body: FutureBuilder(
        future: api.dio.get('/ruptures'),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final ruptures = snapshot.data!.data as List;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.warning_amber, color: Colors.orange),
                  title: Text('${ruptures.length} rupture(s) ouverte(s) sur le réseau'),
                  subtitle: const Text('Toutes interfaces confondues'),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Prochaines étapes de cet écran : reproduire la carte du réseau, le flux '
                'temps réel (RealtimeService déjà branché), et les onglets Réseau / '
                'Statistiques / Notifications / Catalogue de la maquette HTML.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          );
        },
      ),
    );
  }
}
