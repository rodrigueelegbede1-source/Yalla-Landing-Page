import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/graphique_barres.dart';
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
      supabase
          .from('v_carnet_distributeur')
          .select()
          .order('date_signalement', ascending: false),
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
            final boutiques =
                donnees['boutiques'] as List<Map<String, dynamic>>;
            final attribuees =
                courses.where((c) => c['cercle'] == 'attribue').length;
            final elargies =
                courses.where((c) => c['cercle'] == 'elargi').length;
            final actifs = flotte.where((l) => l['actif'] == true).toList();
            final enLigne = actifs.where((l) => l['en_ligne'] == true).length;
            final points = boutiques
                .map((b) => b['point_de_vente_id'])
                .whereType<String>()
                .toSet()
                .length;
            final largeurCarte = (MediaQuery.sizeOf(context).width - 48) / 2;
            final parProduit = <String, int>{};
            for (final course in courses) {
              final produit = course['produit_nom'] as String? ?? 'Produit';
              parProduit.update(produit, (nombre) => nombre + 1,
                  ifAbsent: () => 1);
            }
            final classement = parProduit.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final principaux = classement.take(5).toList();
            final maintenant = DateTime.now();
            final debut =
                DateTime(maintenant.year, maintenant.month, maintenant.day)
                    .subtract(const Duration(days: 6));
            final activite = List.generate(7, (_) => [0, 0]);
            for (final course in courses) {
              final date =
                  DateTime.tryParse('${course['date_signalement'] ?? ''}')
                      ?.toLocal();
              if (date == null) continue;
              final jour = DateTime(date.year, date.month, date.day)
                  .difference(debut)
                  .inDays;
              if (jour < 0 || jour >= activite.length) continue;
              if (course['cercle'] == 'attribue') {
                activite[jour][0]++;
              } else if (course['cercle'] == 'elargi') {
                activite[jour][1]++;
              }
            }
            int coursesEnCours(Map<String, dynamic> livreur) =>
                (livreur['courses_en_cours'] as num?)?.toInt() ?? 0;
            final enCourse = actifs.where((l) => coursesEnCours(l) > 0).length;
            final disponibles = actifs
                .where((l) => l['en_ligne'] == true && coursesEnCours(l) == 0)
                .length;
            final horsLigne = actifs.length - enLigne;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                const TitreSection('Votre activité',
                    detail: 'Réseau en direct'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _IndicateurDistributeur(
                        largeur: largeurCarte,
                        nom: 'Courses ouvertes',
                        valeur: '${courses.length}',
                        icone: Icons.assignment_outlined,
                        alerte: courses.isNotEmpty),
                    _IndicateurDistributeur(
                        largeur: largeurCarte,
                        nom: 'Livreurs en ligne',
                        valeur: '$enLigne / ${actifs.length}',
                        icone: Icons.delivery_dining_outlined),
                    _IndicateurDistributeur(
                        largeur: largeurCarte,
                        nom: 'Boutiques desservies',
                        valeur: '$points',
                        icone: Icons.storefront_outlined),
                    _IndicateurDistributeur(
                        largeur: largeurCarte,
                        nom: 'Courses élargies',
                        valeur: '$elargies',
                        icone: Icons.public_outlined,
                        alerte: elargies > 0),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Carnet de courses',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        _CercleCourse(
                            libelle: 'Attribuées à votre réseau',
                            nombre: attribuees,
                            total: courses.length,
                            couleur: Jetons.vert700),
                        const SizedBox(height: 12),
                        _CercleCourse(
                            libelle: 'Ouvertes dans la commune',
                            nombre: elargies,
                            total: courses.length,
                            couleur: Jetons.jaune),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GraphiqueBarres(
                  titre: 'Courses ouvertes · 7 derniers jours',
                  series: const [
                    SerieGraphique(nom: 'Attribuées', couleur: Jetons.vert700),
                    SerieGraphique(nom: 'Élargies', couleur: Jetons.jaune),
                  ],
                  points: List.generate(7, (index) {
                    final date = debut.add(Duration(days: index));
                    return PointGraphique(
                      libelle: '${date.day}/${date.month}',
                      valeurs: activite[index],
                    );
                  }),
                ),
                TitreSection('Produits les plus demandés',
                    detail: '${courses.length} courses'),
                if (principaux.isEmpty)
                  const Card(
                      child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Aucune course ouverte pour le moment.')))
                else
                  GraphiqueBarres(
                    titre: 'Courses ouvertes par produit',
                    series: const [
                      SerieGraphique(nom: 'Courses', couleur: Jetons.vert700),
                    ],
                    points: principaux
                        .map((produit) => PointGraphique(
                              libelle: produit.key,
                              valeurs: [produit.value],
                            ))
                        .toList(),
                  ),
                GraphiqueBarres(
                  titre: 'État de la flotte active',
                  series: const [
                    SerieGraphique(nom: 'Livreurs', couleur: Jetons.vert700),
                  ],
                  points: [
                    PointGraphique(libelle: 'En course', valeurs: [enCourse]),
                    PointGraphique(
                        libelle: 'Disponibles', valeurs: [disponibles]),
                    PointGraphique(libelle: 'Hors ligne', valeurs: [horsLigne]),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.groups_outlined,
                        color: Jetons.vert700),
                    title: const Text('État de la flotte',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${actifs.length} livreurs actifs · $enLigne en ligne · ${actifs.length - enLigne} hors ligne'),
                  ),
                ),
              ],
            );
          },
        ),
      );
}

class _CercleCourse extends StatelessWidget {
  const _CercleCourse(
      {required this.libelle,
      required this.nombre,
      required this.total,
      required this.couleur});

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
          Text('$nombre',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      );
}

class _IndicateurDistributeur extends StatelessWidget {
  const _IndicateurDistributeur(
      {required this.largeur,
      required this.nom,
      required this.valeur,
      required this.icone,
      this.alerte = false});

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
                Icon(icone,
                    color: alerte ? Jetons.alerte : Jetons.vert700, size: 20),
                const SizedBox(height: 12),
                Text(valeur,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w700, height: 1)),
                const SizedBox(height: 5),
                Text(nom, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      );
}
