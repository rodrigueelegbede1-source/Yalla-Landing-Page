import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/auth/auth_providers.dart';

/// Reprend le formulaire "Nouveau point de vente" de la maquette Agent
/// recenseur, avec capture réelle du GPS du téléphone plutôt qu'un bouton
/// simulé, et l'envoi vers POST /points-de-vente.
class AgentRecenseurHomeScreen extends ConsumerStatefulWidget {
  const AgentRecenseurHomeScreen({super.key});

  @override
  ConsumerState<AgentRecenseurHomeScreen> createState() => _AgentRecenseurHomeScreenState();
}

class _AgentRecenseurHomeScreenState extends ConsumerState<AgentRecenseurHomeScreen> {
  final _nomCtrl = TextEditingController();
  final _communeCtrl = TextEditingController();
  Position? _position;
  bool _enregistrement = false;

  Future<void> _capturerPosition() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    final position = await Geolocator.getCurrentPosition();
    setState(() => _position = position);
  }

  Future<void> _enregistrer() async {
    if (_position == null) return;
    setState(() => _enregistrement = true);
    try {
      await ref.read(apiClientProvider).dio.post('/points-de-vente', data: {
        'nom': _nomCtrl.text,
        'typeActivite': 'superette',
        'commune': _communeCtrl.text,
        'latitude': _position!.latitude,
        'longitude': _position!.longitude,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Point de vente enregistré')),
        );
        _nomCtrl.clear();
        _communeCtrl.clear();
        setState(() => _position = null);
      }
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  // Sur un ConsumerState, 'ref' est deja un membre de la classe. L'ajouter en
  // parametre casse la signature heritee de State.build() et le fichier ne
  // compile pas.
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(session.nom ?? 'Agent recenseur'),
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
            TextField(controller: _nomCtrl, decoration: const InputDecoration(labelText: 'Nom du point de vente')),
            const SizedBox(height: 12),
            TextField(controller: _communeCtrl, decoration: const InputDecoration(labelText: 'Commune')),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              icon: const Icon(Icons.my_location),
              label: Text(_position == null ? 'Capturer la position GPS' : 'Position capturée'),
              onPressed: _capturerPosition,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _position == null || _enregistrement ? null : _enregistrer,
              child: _enregistrement
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enregistrer le point de vente'),
            ),
          ],
        ),
      ),
    );
  }
}
