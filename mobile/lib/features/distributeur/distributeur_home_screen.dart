import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_providers.dart';

/// Reprend l'onglet Courses de la maquette Distributeur : le carnet de courses,
/// séparé en deux cercles (GET /ruptures/distributeur, déjà filtré côté API par
/// la vue `v_acces_rupture_distributeur`).
///
/// La distinction entre les deux cercles est le cœur de l'écran, pas une
/// décoration : une course `attribue` revient de droit au distributeur, une
/// course `elargi` lui parvient parce qu'un confrère ne l'a pas prise dans le
/// délai. La seconde est une opportunité, pas une obligation, et l'interface
/// doit le dire.
///
/// L'identifiant du distributeur n'est pas passé dans l'URL : le backend le lit
/// dans le token, pour qu'un distributeur ne puisse pas consulter le carnet
/// d'un concurrent.
class DistributeurHomeScreen extends ConsumerWidget {
  const DistributeurHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiClientProvider);
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(session.nom ?? 'Distributeur'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(sessionProvider.notifier).deconnecter(),
          ),
        ],
      ),
      body: FutureBuilder(
        future: api.dio.get('/ruptures/distributeur'),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final courses = snapshot.data!.data as List;
          if (courses.isEmpty) {
            return const Center(child: Text('Aucune course en attente.'));
          }

          final attribuees = courses.where((c) => c['cercle'] == 'attribue').toList();
          final elargies = courses.where((c) => c['cercle'] == 'elargi').toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (attribuees.isNotEmpty) ...[
                _Titre('Mes courses', '${attribuees.length} en attente'),
                ...attribuees.map((c) => _CarteCourse(course: c, elargie: false)),
              ],
              if (elargies.isNotEmpty) ...[
                _Titre('Ouvertes dans ma commune', '${elargies.length} disponible(s)'),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Non prises par leur distributeur attribué dans le délai. '
                    'Elles ne vous parviennent que sur les marques que vous portez.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
                ...elargies.map((c) => _CarteCourse(course: c, elargie: true)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Titre extends StatelessWidget {
  const _Titre(this.texte, this.detail);

  final String texte;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(texte, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          Text(detail, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }
}

class _CarteCourse extends StatelessWidget {
  const _CarteCourse({required this.course, required this.elargie});

  final dynamic course;
  final bool elargie;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          elargie ? Icons.public : Icons.error_outline,
          color: elargie ? Colors.blueGrey : Colors.orange,
        ),
        title: Text(course['produit_nom'] ?? ''),
        subtitle: Text('${course['point_de_vente_nom']} — ${course['commune']}'),
        trailing: elargie
            ? const Chip(
                label: Text('ÉLARGIE', style: TextStyle(fontSize: 10)),
                visualDensity: VisualDensity.compact,
              )
            : null,
      ),
    );
  }
}
