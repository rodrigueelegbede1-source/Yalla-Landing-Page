import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/vignette_produit.dart';
import '../../core/widgets.dart';
import '../../l10n/app_localizations.dart';

class DemandesTab extends StatefulWidget {
  const DemandesTab({
    super.key,
    required this.cle,
    required this.pointDeVenteId,
    required this.onChangement,
  });

  final int cle;
  final String pointDeVenteId;
  final VoidCallback onChangement;

  @override
  State<DemandesTab> createState() => _DemandesTabState();
}

class _DemandesTabState extends State<DemandesTab> {
  int _vue = 0;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
          child: SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 0, label: Text(l.demandesEnCours)),
              ButtonSegment(value: 1, label: Text(l.demandesHistorique)),
            ],
            selected: {_vue},
            onSelectionChanged: (selection) =>
                setState(() => _vue = selection.first),
          ),
        ),
        Expanded(
          child: _HistoriqueDemandes(
            cle: widget.cle,
            pointDeVenteId: widget.pointDeVenteId,
            historique: _vue == 1,
          ),
        ),
      ],
    );
  }
}

class _HistoriqueDemandes extends StatefulWidget {
  const _HistoriqueDemandes({
    required this.cle,
    required this.pointDeVenteId,
    required this.historique,
  });

  final int cle;
  final String pointDeVenteId;
  final bool historique;

  @override
  State<_HistoriqueDemandes> createState() => _HistoriqueDemandesState();
}

class _HistoriqueDemandesState extends State<_HistoriqueDemandes> {
  late Future<List<Map<String, dynamic>>> _demandes;

  @override
  void initState() {
    super.initState();
    _demandes = _charger();
  }

  @override
  void didUpdateWidget(_HistoriqueDemandes ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.cle != widget.cle) _rafraichir();
  }

  Future<List<Map<String, dynamic>>> _charger() async {
    final lignes = await supabase
        .from('ruptures')
        .select(
          'id, statut, quantite_demandee, date_signalement, date_resolution, '
          'produits(nom, image_url)',
        )
        .eq('point_de_vente_id', widget.pointDeVenteId)
        .not('confirmee_le', 'is', null)
        .order('date_signalement', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(lignes);
  }

  Future<void> _rafraichir() async {
    final f = _charger();
    if (mounted) setState(() => _demandes = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();

    return RefreshIndicator(
      onRefresh: _rafraichir,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _demandes,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return EtatVide(
              icone: Icons.cloud_off_outlined,
              titre: l.chargementImpossible,
              message: messageErreur(context, snap.error!),
            );
          }

          final demandes = (snap.data ?? const []).where((demande) {
            final statut = demande['statut'] as String?;
            final active = statut == 'signalee' || statut == 'prise_en_charge';
            return widget.historique ? !active : active;
          }).toList();
          if (demandes.isEmpty) {
            return EtatVide(
              icone: Icons.receipt_long_outlined,
              titre: widget.historique
                  ? l.demandesHistoriqueVideTitre
                  : l.demandesActivesVidesTitre,
              message: widget.historique
                  ? l.demandesHistoriqueVideMessage
                  : l.demandesActivesVidesMessage,
            );
          }

          return ListView.builder(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
            itemCount: demandes.length,
            itemBuilder: (context, index) {
              final demande = demandes[index];
              final produit =
                  demande['produits'] as Map<String, dynamic>? ?? {};
              final statut = demande['statut'] as String? ?? '';
              final date = DateTime.tryParse(
                demande['date_signalement']?.toString() ?? '',
              );
              final dateAffichee = date == null
                  ? ''
                  : DateFormat.yMd(locale).add_Hm().format(date.toLocal());
              final (libelle, couleur, icone) = switch (statut) {
                'signalee' => (
                    l.demandeEnAttente,
                    Colors.orange,
                    Icons.schedule
                  ),
                'prise_en_charge' => (
                    l.demandeEnCours,
                    Colors.blue,
                    Icons.local_shipping_outlined
                  ),
                'resolue' => (
                    l.demandeTerminee,
                    Colors.green,
                    Icons.check_circle_outline
                  ),
                _ => (l.demandeNonServie, Colors.blueGrey, Icons.info_outline),
              };

              return Card(
                margin: const EdgeInsetsDirectional.only(bottom: 10),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: VignetteProduit(
                    nom: produit['nom'] as String? ?? '',
                    imageUrl: produit['image_url'] as String?,
                    taille: 48,
                  ),
                  title: Text(
                    produit['nom'] as String? ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      [
                        if (demande['quantite_demandee'] != null)
                          l.cartons(
                              (demande['quantite_demandee'] as num).toInt()),
                        if (dateAffichee.isNotEmpty)
                          l.demandeDate(dateAffichee),
                      ].join(' · '),
                    ),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icone, color: couleur, size: 20),
                      const SizedBox(height: 4),
                      Text(
                        libelle,
                        style: TextStyle(
                          color: couleur,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
