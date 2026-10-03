import 'package:flutter/material.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class DistributeurApercuTab extends StatefulWidget {
  const DistributeurApercuTab({super.key, required this.cle});

  final int cle;

  @override
  State<DistributeurApercuTab> createState() => _DistributeurApercuTabState();
}

class _DistributeurApercuTabState extends State<DistributeurApercuTab> {
  late Future<Map<String, dynamic>> _donnees;

  @override
  void initState() {
    super.initState();
    _donnees = _charger();
  }

  @override
  void didUpdateWidget(DistributeurApercuTab ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.cle != widget.cle) _rafraichir();
  }

  Future<Map<String, dynamic>> _charger() async {
    final reponses = await Future.wait<Object?>([
      supabase.from('v_carnet_distributeur').select().order('date_signalement', ascending: false),
      supabase.from('v_ma_flotte').select().order('nom'),
      supabase.from('v_mon_reseau').select().order('commune'),
    ]);
    return {
      'courses': List<Map<String, dynamic>>.from(reponses[0] as List),
      'flotte': List<Map<String, dynamic>>.from(reponses[1] as List),
      'boutiques': List<Map<String, dynamic>>.from(reponses[2] as List),
    };
  }

  Future<void> _rafraichir() async {
    final future = _charger();
    if (mounted) setState(() => _donnees = future);
    await future;
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _rafraichir,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _donnees,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return EtatVide(
                icone: Icons.cloud_off_outlined,
                titre: 'Aperçu indisponible',
                message: messageErreur(context, snap.error!),
              );
            }

            final donnees = snap.data!;
            final courses = donnees['courses'] as List<Map<String, dynamic>>;
            final flotte = donnees['flotte'] as List<Map<String, dynamic>>;
            final boutiques = donnees['boutiques'] as List<Map<String, dynamic>>;
            final attribuees = courses.where((c) => c['cercle'] == 'attribue').length;
            final elargies = courses.where((c) => c['cercle'] == 'elargi').length;
            final actifs = flotte.where((l) => l['actif'] == true).toList();
            final enLigne = actifs.where((l) => l['en_ligne'] == true).length;
            final points = boutiques.map((b) => b['point_de_vente_id']).whereType<String>().toSet().length;
            final largeurCarte = (MediaQuery.sizeOf(context).width - 48) / 2;
            final parProduit = <String, int>{};
            for (final course in courses) {
              final produit = course['produit_nom'] as String? ?? 'Produit';
              parProduit.update(produit, (nombre) => nombre + 1, ifAbsent: () => 1);
            }
            final classement = parProduit.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final principaux = classement.take(5).toList();
            final maximum = principaux.fold<int>(
              1,
              (max, produit) => produit.value > max ? produit.value : max,
            );

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                TitreSection('Votre activité', detail: 'Réseau en direct'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _IndicateurDistributeur(largeur: largeurCarte, nom: 'Courses ouvertes', valeur: '${courses.length}', icone: Icons.assignment_outlined, alerte: courses.isNotEmpty),
                    _IndicateurDistributeur(largeur: largeurCarte, nom: 'Livreurs en ligne', valeur: '$enLigne / ${actifs.length}', icone: Icons.delivery_dining_outlined),
                    _IndicateurDistributeur(largeur: largeurCarte, nom: 'Boutiques desservies', valeur: '$points', icone: Icons.storefront_outlined),
                    _IndicateurDistributeur(largeur: largeurCarte, nom: 'Courses élargies', valeur: '$elargies', icone: Icons.public_outlined, alerte: elargies > 0),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Carnet de courses', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        _CercleCourse(libelle: 'Attribuées à votre réseau', nombre: attribuees, total: courses.length, couleur: Jetons.vert700),
                        const SizedBox(height: 12),
                        _CercleCourse(libelle: 'Ouvertes dans la commune', nombre: elargies, total: courses.length, couleur: Jetons.jaune),
                      ],
                    ),
                  ),
                ),
                TitreSection('Produits les plus demandés', detail: '${courses.length} courses'),
                if (principaux.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Aucune course ouverte pour le moment.')))
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: principaux.map((produit) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [Expanded(child: Text(produit.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))), Text('${produit.value}')]),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(value: produit.value / maximum, minHeight: 5, borderRadius: BorderRadius.circular(4)),
                            ],
                          ),
                        )).toList(),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.groups_outlined, color: Jetons.vert700),
                    title: const Text('État de la flotte', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${actifs.length} livreurs actifs · $enLigne en ligne · ${actifs.length - enLigne} hors ligne'),
                  ),
                ),
              ],
            );
          },
        ),
      );
}

class _CercleCourse extends StatelessWidget {
  const _CercleCourse({required this.libelle, required this.nombre, required this.total, required this.couleur});

  final String libelle;
  final int nombre;
  final int total;
  final Color couleur;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(
            width: 38,
            height: 38,
            child: CircularProgressIndicator(
              value: total == 0 ? 0 : nombre / total,
              color: couleur,
              backgroundColor: Jetons.creme2,
              strokeWidth: 5,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(libelle, style: const TextStyle(fontSize: 13))),
          Text('$nombre', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      );
}

class _IndicateurDistributeur extends StatelessWidget {
  const _IndicateurDistributeur({required this.largeur, required this.nom, required this.valeur, required this.icone, this.alerte = false});

  final double largeur;
  final String nom;
  final String valeur;
  final IconData icone;
  final bool alerte;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: largeur,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icone, color: alerte ? Jetons.alerte : Jetons.vert700, size: 20),
                const SizedBox(height: 12),
                Text(valeur, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1)),
                const SizedBox(height: 5),
                Text(nom, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      );
}