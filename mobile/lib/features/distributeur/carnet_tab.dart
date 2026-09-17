import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/widgets.dart';

/// Carnet de courses du distributeur.
///
/// Reprend l'écran « Courses » de la maquette, et sa distinction centrale :
/// les courses **attribuées**, qui lui reviennent de droit, et les courses
/// **élargies**, qu'un confrère n'a pas prises dans le délai. La seconde
/// catégorie est une opportunité, pas une obligation, et l'interface doit le
/// montrer sans ambiguïté.
///
/// Le filtrage n'est pas fait ici : la vue `v_carnet_distributeur` est soumise
/// aux politiques RLS, donc la requête ne peut rendre que ce que ce
/// distributeur a le droit de voir. Aucun identifiant n'est envoyé depuis le
/// téléphone, il est lu dans le jeton par la base.
class CarnetTab extends StatefulWidget {
  const CarnetTab({super.key, required this.cle, required this.onChangement});

  /// Change à chaque évènement temps réel. Voir `core/temps_reel.dart`.
  final int cle;

  final VoidCallback onChangement;

  @override
  State<CarnetTab> createState() => _CarnetTabState();
}

class _CarnetTabState extends State<CarnetTab> {
  late Future<List<Map<String, dynamic>>> _courses;

  @override
  void initState() {
    super.initState();
    _courses = _charger();
  }

  @override
  void didUpdateWidget(CarnetTab ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.cle != widget.cle) _rafraichir();
  }

  Future<List<Map<String, dynamic>>> _charger() async {
    final lignes = await supabase
        .from('v_carnet_distributeur')
        .select()
        .order('cercle')
        .order('date_signalement', ascending: false);
    return List<Map<String, dynamic>>.from(lignes);
  }

  Future<void> _rafraichir() async {
    final f = _charger();
    if (mounted) setState(() => _courses = f);
    await f;
  }

  /// Affecte un livreur de sa flotte à la course.
  ///
  /// Passe par la fonction `affecter_livreur`, qui porte le verrou : elle
  /// vérifie que le livreur appartient bien à cette flotte, qu'il n'en a pas été
  /// écarté, et que la course est encore libre. Deux distributeurs qui cliquent
  /// en même temps : un seul gagne.
  Future<void> _affecter(String ruptureId) async {
    // `v_ma_flotte` joint le nom, ce que la table seule ne permettait pas : la
    // politique RLS sur `utilisateurs` ne laisse lire que soi-même, et la liste
    // affichait « Livreur » pour tout le monde. Une politique dédiée a été
    // ajoutée avec la vue.
    final livreurs = List<Map<String, dynamic>>.from(
      await supabase.from('v_ma_flotte').select().eq('actif', true).order('en_ligne', ascending: false),
    );

    if (!mounted) return;
    if (livreurs.isEmpty) {
      _message('Aucun livreur actif dans votre flotte. Ajoutez-en un dans l\'onglet Flotte.');
      return;
    }

    final choix = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Affecter à un livreur',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ...livreurs.map((l) {
              final enLigne = l['en_ligne'] == true;
              final enCours = (l['courses_en_cours'] as num?)?.toInt() ?? 0;
              return ListTile(
                leading: Icon(Icons.local_shipping_outlined,
                    color: enLigne ? Colors.green : Colors.grey),
                title: Text(l['nom'] as String? ?? 'Livreur'),
                subtitle: Text(
                  enLigne
                      ? (enCours > 0 ? 'En ligne · $enCours course(s) en cours' : 'En ligne, disponible')
                      : 'Hors ligne, il ne verra la course qu\'à sa reconnexion',
                ),
                onTap: () => Navigator.pop(context, l['livreur_id'] as String),
              );
            }),
          ],
        ),
      ),
    );

    if (choix == null) return;

    try {
      await supabase.rpc('affecter_livreur',
          params: {'p_rupture_id': ruptureId, 'p_livreur_id': choix});
      _message('Course affectée');
      widget.onChangement();
      await _rafraichir();
    } catch (e) {
      _message(messageErreur(e));
    }
  }

  void _message(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texte)));
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
            return EtatVide(
              icone: Icons.cloud_off_outlined,
              titre: 'Chargement impossible',
              message: messageErreur(snap.error!),
            );
          }

          final courses = snap.data ?? const [];
          if (courses.isEmpty) {
            return const EtatVide(
              icone: Icons.check_circle_outline,
              titre: 'Aucune course en attente',
              message: 'Vos boutiques sont servies. Les nouvelles ruptures '
                  'apparaîtront ici dès qu\'elles seront signalées, sans rien toucher.',
            );
          }

          final attribuees = courses.where((c) => c['cercle'] == 'attribue').toList();
          final elargies = courses.where((c) => c['cercle'] == 'elargi').toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (attribuees.isNotEmpty) ...[
                TitreSection('Mes courses', detail: '${attribuees.length} en attente'),
                ...attribuees.map((c) => _Course(
                      course: c,
                      onAffecter: () => _affecter(c['rupture_id'] as String),
                    )),
              ],
              if (elargies.isNotEmpty) ...[
                TitreSection('Ouvertes dans ma commune',
                    detail: '${elargies.length} disponible(s)'),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Non prises par leur distributeur attribué dans le délai. '
                    'Elles ne vous parviennent que sur les marques que vous portez. '
                    'Premier arrivé, premier servi.',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
                ...elargies.map((c) => _Course(
                      course: c,
                      onAffecter: () => _affecter(c['rupture_id'] as String),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Course extends StatelessWidget {
  const _Course({required this.course, required this.onAffecter});

  final Map<String, dynamic> course;
  final VoidCallback onAffecter;

  @override
  Widget build(BuildContext context) {
    final elargie = course['cercle'] == 'elargi';
    final dejaPrise = course['statut'] == 'prise_en_charge';
    final secondes = (course['secondes_avant_escalade'] as num?)?.toInt() ?? 0;
    final quantite = course['quantite_demandee'] as int?;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(elargie ? Icons.public : Icons.inventory_2_outlined,
                    color: elargie ? Colors.blueGrey : Colors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(course['produit_nom'] as String? ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        '${course['point_de_vente_nom']} · ${course['commune']}'
                        '${quantite != null ? ' · $quantite carton(s)' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(depuis(course['anciennete_secondes'] as num?),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (elargie)
                  const Etiquette(texte: 'ÉLARGIE', couleur: Colors.blueGrey)
                else if (secondes > 0)
                  Etiquette(
                    texte: 'OUVERTE AUX AUTRES DANS ${duree(secondes)}',
                    couleur: Colors.orange,
                  )
                else
                  const Etiquette(texte: 'DÉLAI DÉPASSÉ', couleur: Colors.red),
                const Spacer(),
                if (dejaPrise)
                  const Text('Affectée', style: TextStyle(fontSize: 12))
                else
                  FilledButton.tonal(
                    onPressed: onAffecter,
                    child: const Text('Affecter'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
