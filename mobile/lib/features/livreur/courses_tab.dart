import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/supabase.dart';

/// Les ruptures que ce livreur peut prendre, triées par distance.
///
/// Le tri est calculé par PostGIS, pas en Dart : `courses_a_proximite()` utilise
/// l'opérateur de plus proche voisin et l'index spatial. Trier côté client
/// obligerait à télécharger tout le réseau pour n'en afficher que dix lignes.
///
/// Prendre une course crée la livraison dans la même transaction. Le livreur la
/// retrouve donc immédiatement dans l'onglet Mes courses.
class CoursesTab extends StatefulWidget {
  const CoursesTab({super.key, required this.cle, required this.onCoursePrise});

  /// Change quand une course a été livrée ou abandonnée ailleurs : une course
  /// abandonnée réapparaît ici.
  final int cle;

  final VoidCallback onCoursePrise;

  @override
  State<CoursesTab> createState() => _CoursesTabState();
}

class _CoursesTabState extends State<CoursesTab> {
  late Future<List<Map<String, dynamic>>> _courses;

  @override
  void initState() {
    super.initState();
    _courses = _charger();
  }

  @override
  void didUpdateWidget(CoursesTab ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.cle != widget.cle) _rafraichir();
  }

  Future<List<Map<String, dynamic>>> _charger() async {
    final lignes = await supabase.rpc('courses_a_proximite', params: {'p_limite': 20});
    return List<Map<String, dynamic>>.from(lignes as List);
  }

  Future<void> _rafraichir() async {
    final f = _charger();
    if (mounted) setState(() => _courses = f);
    await f;
  }

  Future<void> _prendre(String ruptureId) async {
    try {
      await supabase.rpc('prendre_rupture', params: {'p_rupture_id': ruptureId});
      _message('Course prise. Retrouvez-la dans Mes courses.');
      widget.onCoursePrise();
    } catch (e) {
      // Cas le plus fréquent et le plus important : un autre livreur a été plus
      // rapide. Le message vient de la base, il est déjà écrit pour être lu.
      if (!mounted) return;
      _message(messageErreur(context, e));
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
    return RefreshIndicator(
      onRefresh: _rafraichir,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _courses,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ListView(children: [
              const SizedBox(height: 80),
              Center(child: Text(messageErreur(context, snap.error!))),
            ]);
          }

          final courses = snap.data ?? const [];
          if (courses.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 100),
              Icon(Icons.check_circle_outline, size: 56),
              SizedBox(height: 20),
              Text('Aucune course à proximité',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Les ruptures de votre secteur apparaîtront ici dès qu\'une '
                  'boutique en signalera une.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ]);
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
                    style: boutonBoutDeLigne,
                    child: const Text('Prendre'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
