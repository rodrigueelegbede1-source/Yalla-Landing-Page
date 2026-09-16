import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/format.dart';
import '../../core/supabase.dart';

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
class DistributeurHomeScreen extends ConsumerStatefulWidget {
  const DistributeurHomeScreen({super.key, required this.distributeurId});

  final String distributeurId;

  @override
  ConsumerState<DistributeurHomeScreen> createState() => _DistributeurHomeScreenState();
}

class _DistributeurHomeScreenState extends ConsumerState<DistributeurHomeScreen> {
  late Future<List<Map<String, dynamic>>> _courses;

  @override
  void initState() {
    super.initState();
    _courses = _charger();
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
    setState(() => _courses = f);
    await f;
  }

  /// Affecte un livreur de sa flotte à la course.
  ///
  /// Passe par la fonction `affecter_livreur`, qui porte le verrou : elle
  /// vérifie que le livreur appartient bien à cette flotte et que la course est
  /// encore libre. Deux distributeurs qui cliquent en même temps : un seul gagne.
  Future<void> _affecter(String ruptureId) async {
    final livreurs = List<Map<String, dynamic>>.from(
      await supabase.from('livreurs').select('id, en_ligne, utilisateurs(nom)'),
    );

    if (!mounted) return;
    if (livreurs.isEmpty) {
      _message('Aucun livreur rattaché à votre flotte');
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
              final nom = (l['utilisateurs'] as Map?)?['nom'] as String? ?? 'Livreur';
              return ListTile(
                leading: Icon(Icons.local_shipping_outlined,
                    color: enLigne ? Colors.green : Colors.grey),
                title: Text(nom),
                subtitle: Text(enLigne ? 'En ligne' : 'Hors ligne'),
                onTap: () => Navigator.pop(context, l['id'] as String),
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
    final session = ref.watch(sessionProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(session?.nom ?? 'Distributeur'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Se déconnecter',
            onPressed: () => ref.read(authProvider).deconnecter(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _rafraichir,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _courses,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _Vide(
                icone: Icons.cloud_off_outlined,
                titre: 'Chargement impossible',
                message: messageErreur(snap.error!),
              );
            }

            final courses = snap.data ?? const [];
            if (courses.isEmpty) {
              return const _Vide(
                icone: Icons.check_circle_outline,
                titre: 'Aucune course en attente',
                message: 'Vos boutiques sont servies. Les nouvelles ruptures '
                    'apparaîtront ici dès qu\'elles seront signalées.',
              );
            }

            final attribuees = courses.where((c) => c['cercle'] == 'attribue').toList();
            final elargies = courses.where((c) => c['cercle'] == 'elargi').toList();

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (attribuees.isNotEmpty) ...[
                  _Titre('Mes courses', '${attribuees.length} en attente'),
                  ...attribuees.map((c) => _Course(
                        course: c,
                        onAffecter: () => _affecter(c['rupture_id'] as String),
                      )),
                ],
                if (elargies.isNotEmpty) ...[
                  _Titre('Ouvertes dans ma commune', '${elargies.length} disponible(s)'),
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
      ),
    );
  }
}

class _Titre extends StatelessWidget {
  const _Titre(this.texte, this.detail);
  final String texte;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(texte, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text(detail, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
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
                  const _Etiquette(texte: 'ÉLARGIE', couleur: Colors.blueGrey)
                else if (secondes > 0)
                  _Etiquette(
                    texte: 'OUVERTE AUX AUTRES DANS ${duree(secondes)}',
                    couleur: Colors.orange,
                  )
                else
                  const _Etiquette(texte: 'DÉLAI DÉPASSÉ', couleur: Colors.red),
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

class _Etiquette extends StatelessWidget {
  const _Etiquette({required this.texte, required this.couleur});
  final String texte;
  final Color couleur;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(texte,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: couleur)),
      );
}

class _Vide extends StatelessWidget {
  const _Vide({required this.icone, required this.titre, required this.message});
  final IconData icone;
  final String titre;
  final String message;

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
            child: Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, height: 1.5)),
          ),
        ],
      );
}
