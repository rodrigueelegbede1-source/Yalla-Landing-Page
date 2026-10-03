import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';

class FabricantApercuTab extends StatelessWidget {
  const FabricantApercuTab({super.key, required this.future, required this.cle});

  final Future<Map<String, dynamic>> future;
  final int cle;

  int _nombre(dynamic value) => (value as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        key: ValueKey(cle),
        future: future,
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
          final catalogue = donnees['catalogue'] as List<Map<String, dynamic>>;
          final ruptures = donnees['ruptures'] as List<Map<String, dynamic>>;
          final actives = ruptures
              .where((r) => r['statut'] == 'signalee' || r['statut'] == 'prise_en_charge')
              .toList();
          final quantites = actives.fold<int>(
            0,
            (total, r) => total + _nombre(r['quantite_demandee']),
          );
          final service = donnees['service'] as Map<String, dynamic>?;
          final taux = ((service?['taux_de_service_pct'] as num?)?.toDouble() ?? 0)
              .clamp(0, 100);
          final produits = [...catalogue]
            ..sort((a, b) => _nombre(b['ruptures_ouvertes'])
                .compareTo(_nombre(a['ruptures_ouvertes'])));
          final plusDemandes = produits.take(4).toList();
          final maxDemandes = plusDemandes.fold<int>(
            0,
            (max, p) => _nombre(p['ruptures_ouvertes']) > max
                ? _nombre(p['ruptures_ouvertes'])
                : max,
          );

          final maintenant = DateTime.now();
          final debut = DateTime(maintenant.year, maintenant.month, maintenant.day)
              .subtract(const Duration(days: 6));
          final activite = List<int>.filled(7, 0);
          for (final rupture in ruptures) {
            final date = DateTime.tryParse('${rupture['date_signalement'] ?? ''}')
                ?.toLocal();
            if (date == null) continue;
            final jour = DateTime(date.year, date.month, date.day)
                .difference(debut)
                .inDays;
            if (jour >= 0 && jour < activite.length) activite[jour]++;
          }
          final pic = activite.fold<int>(
            1,
            (max, count) => count > max ? count : max,
          );
          final largeurCarte = (MediaQuery.sizeOf(context).width - 48) / 2;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            children: [
              TitreSection('Mon activité', detail: 'Données de mon catalogue'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _IndicateurFabricant(
                    largeur: largeurCarte,
                    libelle: 'Ruptures en cours',
                    valeur: '${actives.length}',
                    icone: Icons.warning_amber_outlined,
                    couleur: Jetons.alerte,
                  ),
                  _IndicateurFabricant(
                    largeur: largeurCarte,
                    libelle: 'Quantités demandées',
                    valeur: '$quantites',
                    icone: Icons.inventory_2_outlined,
                    couleur: Jetons.vert700,
                  ),
                  _IndicateurFabricant(
                    largeur: largeurCarte,
                    libelle: 'Références actives',
                    valeur: '${catalogue.where((p) => p['disponible'] == true).length}',
                    icone: Icons.sell_outlined,
                    couleur: Jetons.vert700,
                  ),
                  _IndicateurFabricant(
                    largeur: largeurCarte,
                    libelle: 'Suivis de références',
                    valeur: '${catalogue.fold<int>(0, (total, p) => total + _nombre(p['boutiques_suivant']))}',
                    icone: Icons.storefront_outlined,
                    couleur: Jetons.vert700,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Taux de service', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 5),
                            Text(
                              service == null
                                  ? 'Calculé à la clôture des ruptures'
                                  : 'Livraisons confirmées sur les ruptures closes',
                              style: const TextStyle(fontSize: 13, height: 1.35),
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
                              value: service == null ? 0 : taux / 100,
                              strokeWidth: 7,
                              backgroundColor: Jetons.creme2,
                            ),
                            Text(
                              service == null ? '—' : '${taux.toStringAsFixed(0)}%',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Signalements sur 7 jours', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 116,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: List.generate(7, (index) {
                            final date = debut.add(Duration(days: index));
                            final hauteur = 12.0 + 76.0 * activite[index] / pic;
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsetsDirectional.symmetric(horizontal: 3),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text('${activite[index]}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 5),
                                    Container(
                                      height: hauteur,
                                      decoration: BoxDecoration(
                                        color: index == 6 ? Jetons.jaune : Jetons.vert700,
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text('${date.day}/${date.month}', style: const TextStyle(fontSize: 10)),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              TitreSection('Références les plus signalées', detail: '${catalogue.length} au catalogue'),
              if (plusDemandes.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Catalogue vide. Ajoutez vos références pour suivre les demandes du réseau.'),
                  ),
                )
              else
                ...plusDemandes.map((produit) {
                  final demandes = _nombre(produit['ruptures_ouvertes']);
                  final avancement = maxDemandes == 0 ? 0.0 : demandes / maxDemandes;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  produit['nom'] as String? ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              Text('$demandes ouvertes', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(value: avancement, minHeight: 5, borderRadius: BorderRadius.circular(4)),
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

class _IndicateurFabricant extends StatelessWidget {
  const _IndicateurFabricant({
    required this.largeur,
    required this.libelle,
    required this.valeur,
    required this.icone,
    required this.couleur,
  });

  final double largeur;
  final String libelle;
  final String valeur;
  final IconData icone;
  final Color couleur;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: largeur,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icone, color: couleur, size: 20),
                const SizedBox(height: 12),
                Text(valeur, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1)),
                const SizedBox(height: 5),
                Text(libelle, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      );
}