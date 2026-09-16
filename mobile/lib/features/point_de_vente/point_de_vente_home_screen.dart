import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_providers.dart';

/// Écran d'attente du rôle Point de vente.
///
/// Il ne fait rien d'utile, et il l'annonce. C'est délibéré : la méthode
/// `_signaler()` qui vivait ici appelait l'API NestJS, retirée au profit de
/// Supabase, et son bouton n'était relié à rien. Un bouton actif qui ne
/// déclenche aucune action est pire qu'un bouton désactivé : le boutiquier
/// croit avoir signalé sa rupture.
///
/// Cet écran sera remplacé par les quatre vues de la maquette Point de vente :
/// caisse, stock, signalement et historique. Le signalement passera alors par
/// la fonction `enregistrer_vente()` ou par une insertion directe dans
/// `ruptures`, les deux étant protégées par les politiques RLS qui vérifient
/// que le point de vente signale bien pour lui-même.
class PointDeVenteHomeScreen extends ConsumerWidget {
  const PointDeVenteHomeScreen({super.key, required this.pointDeVenteId});

  final String pointDeVenteId;

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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.storefront_outlined, size: 64),
            const SizedBox(height: 24),
            const Text(
              'Votre caisse arrive',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Encaissez vos ventes, suivez votre stock, et laissez Yalla '
              'prévenir votre distributeur quand un produit tombe à zéro.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            // Volontairement désactivé tant que l'écran de sélection du produit
            // n'existe pas. Voir le commentaire de classe.
            FilledButton.icon(
              icon: const Icon(Icons.warning_amber),
              label: const Text('Signaler une rupture'),
              onPressed: null,
            ),
          ],
        ),
      ),
    );
  }
}
