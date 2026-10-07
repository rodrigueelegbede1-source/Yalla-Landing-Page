import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/graphique_barres.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class AdministrateurApercuTab extends StatelessWidget {
  const AdministrateurApercuTab({
    super.key,
    required this.supervision,
    required this.communes,
    required this.onRefresh,
  });

  final Future<Map<String, dynamic>> supervision;
  final Future<List<Map<String, dynamic>>> communes;
  final Future<void> Function() onRefresh;

  int _nombre(dynamic value) => (value as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: supervision,
        builder: (context, statsSnap) {
          if (statsSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (statsSnap.hasError || statsSnap.data == null) {
            return EtatVide(
              icone: Icons.cloud_off_outlined,
              titre: 'Supervision indisponible',
              message:
                  messageErreur(context, statsSnap.error ?? 'Aucune donnée'),
              action: 'Réessayer',
              onAction: onRefresh,
            );
          }

          final stats = statsSnap.data!;
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: communes,
            builder: (context, communesSnap) {
              if (communesSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (communesSnap.hasError) {
                return EtatVide(
                  icone: Icons.cloud_off_outlined,
                  titre: 'Répartition indisponible',
                  message: messageErreur(context, communesSnap.error!),
                  action: 'Réessayer',
                  onAction: onRefresh,
                );
              }

              final listeCommunes = [...?communesSnap.data]..sort((a, b) =>
                  _nombre(b['points']).compareTo(_nombre(a['points'])));
              final principales = listeCommunes.take(5).toList();
              final communesAvecRuptures = [...listeCommunes]..sort((a, b) =>
                  _nombre(b['ruptures']).compareTo(_nombre(a['ruptures'])));
              final largeurCarte = (MediaQuery.sizeOf(context).width - 48) / 2;
              final taux =
                  ((stats['taux_de_service_pct'] as num?)?.toDouble() ?? 0)
                      .clamp(0, 100);

              return RefreshIndicator(
                onRefresh: onRefresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    const TitreSection('État du réseau', detail: 'Vue agrégée'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _IndicateurAdmin(
                            largeur: largeurCarte,
                            nom: 'Boutiques actives',
                            valeur: _nombre(stats['boutiques_actives']),
                            icone: Icons.storefront_outlined),
                        _IndicateurAdmin(
                            largeur: largeurCarte,
                            nom: 'Ruptures ouvertes',
                            valeur: _nombre(stats['ruptures_ouvertes']),
                            icone: Icons.warning_amber_outlined,
                            alerte: true),
                        _IndicateurAdmin(
                            largeur: largeurCarte,
                            nom: 'Livreurs en ligne',
                            valeur: _nombre(stats['livreurs_en_ligne']),
                            icone: Icons.delivery_dining_outlined),
                        _IndicateurAdmin(
                            largeur: largeurCarte,
                            nom: 'Demandes en attente',
                            valeur: _nombre(stats['demandes_en_attente']),
                            icone: Icons.person_add_alt_1_outlined),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Card(
                      color: Jetons.vert900,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Taux de service du réseau',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 5),
                                  Text(
                                    '${_nombre(stats['ruptures_closes'])} ruptures clôturées · ${_nombre(stats['ruptures_a_confirmer'])} à confirmer',
                                    style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: .78),
                                        fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            SizedBox(
                              width: 68,
                              height: 68,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircularProgressIndicator(
                                      value: taux / 100,
                                      strokeWidth: 7,
                                      color: Jetons.jaune,
                                      backgroundColor: Colors.white24),
                                  Text(
                                      stats['taux_de_service_pct'] == null
                                          ? '—'
                                          : '${taux.toStringAsFixed(0)}%',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    TitreSection('Boutiques par commune',
                        detail: '${listeCommunes.length} communes'),
                    GraphiqueBarres(
                      titre: 'Couverture des boutiques',
                      series: const [
                        SerieGraphique(
                            nom: 'Desservies', couleur: Jetons.vert700),
                        SerieGraphique(
                            nom: 'Sans distributeur', couleur: Jetons.alerte),
                      ],
                      points: principales.map((commune) {
                        final points = _nombre(commune['points']);
                        final sansDistributeur = _nombre(
                          commune['points_sans_distributeur'],
                        ).clamp(0, points).toInt();
                        return PointGraphique(
                          libelle: commune['commune'] as String? ?? 'Commune',
                          valeurs: [
                            points - sansDistributeur,
                            sansDistributeur
                          ],
                        );
                      }).toList(),
                    ),
                    const TitreSection('Ruptures par commune'),
                    GraphiqueBarres(
                      titre: 'Demandes ouvertes',
                      series: const [
                        SerieGraphique(nom: 'Ruptures', couleur: Jetons.alerte),
                      ],
                      points: communesAvecRuptures
                          .where((commune) => _nombre(commune['ruptures']) > 0)
                          .take(5)
                          .map((commune) => PointGraphique(
                                libelle:
                                    commune['commune'] as String? ?? 'Commune',
                                valeurs: [_nombre(commune['ruptures'])],
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 10),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.hub_outlined,
                            color: Jetons.vert700),
                        title: const Text('Réseau en chiffres',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            '${_nombre(stats['fabricants'])} fabricants · ${_nombre(stats['distributeurs'])} distributeurs · ${_nombre(stats['livreurs_actifs'])} livreurs actifs · ${_nombre(stats['produits'])} références'),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
}

class AdministrateurCommunesTab extends StatelessWidget {
  const AdministrateurCommunesTab({super.key, required this.future});

  final Future<List<Map<String, dynamic>>> future;

  int _nombre(dynamic value) => (value as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return EtatVide(
                icone: Icons.cloud_off_outlined,
                titre: 'Réseau indisponible',
                message: messageErreur(context, snap.error!));
          }
          final lignes = [...?snap.data]..sort(
              (a, b) => _nombre(b['points']).compareTo(_nombre(a['points'])));
          final maximum = lignes.fold<int>(
              1,
              (max, row) =>
                  _nombre(row['points']) > max ? _nombre(row['points']) : max);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TitreSection('Couverture territoriale',
                  detail: '${lignes.length} communes'),
              ...lignes.map((row) {
                final points = _nombre(row['points']);
                final ruptures = _nombre(row['ruptures']);
                final sansDistributeur =
                    _nombre(row['points_sans_distributeur']);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(
                                  row['commune'] as String? ??
                                      'Commune non renseignée',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700))),
                          Text('$points points')
                        ]),
                        const SizedBox(height: 9),
                        LinearProgressIndicator(
                            value: points / maximum,
                            minHeight: 7,
                            borderRadius: BorderRadius.circular(4)),
                        const SizedBox(height: 10),
                        Text(
                            '$ruptures ruptures · $sansDistributeur sans distributeur',
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                );
              }),
            ],
          );
        },
      );
}

class AdministrateurAlertesTab extends StatelessWidget {
  const AdministrateurAlertesTab({super.key, required this.future});

  final Future<List<Map<String, dynamic>>> future;

  String _titre(String type) => switch (type) {
        'boutique_sans_distributeur' => 'Boutique sans distributeur',
        'distributeur_sans_livreur' => 'Distributeur sans livreur',
        'rupture_sans_destinataire' => 'Rupture sans destinataire',
        _ => 'Anomalie du réseau',
      };

  IconData _icone(String type) => type.startsWith('boutique_')
      ? Icons.storefront_outlined
      : type.startsWith('distributeur_')
          ? Icons.local_shipping_outlined
          : Icons.warning_amber_outlined;

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return EtatVide(
                icone: Icons.cloud_off_outlined,
                titre: 'Alertes indisponibles',
                message: messageErreur(context, snap.error!));
          }
          final anomalies = snap.data ?? const [];
          if (anomalies.isEmpty) {
            return const EtatVide(
                icone: Icons.check_circle_outline,
                titre: 'Réseau sans anomalie',
                message: 'Aucune panne silencieuse détectée dans le réseau.');
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TitreSection('Points à surveiller',
                  detail: '${anomalies.length} alertes'),
              ...anomalies.map((anomalie) {
                final type = anomalie['type_anomalie'] as String? ?? '';
                return Card(
                  margin: const EdgeInsets.only(bottom: 9),
                  child: ListTile(
                    leading: Icon(_icone(type), color: Jetons.alerte),
                    title: Text(
                        anomalie['objet_nom'] as String? ?? _titre(type),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                          '${_titre(type)} · ${anomalie['detail'] ?? ''}\n${anomalie['consequence'] ?? ''}',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis),
                    ),
                    isThreeLine: true,
                  ),
                );
              }),
            ],
          );
        },
      );
}

class _IndicateurAdmin extends StatelessWidget {
  const _IndicateurAdmin(
      {required this.largeur,
      required this.nom,
      required this.valeur,
      required this.icone,
      this.alerte = false});

  final double largeur;
  final String nom;
  final int valeur;
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
                Text('$valeur',
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
