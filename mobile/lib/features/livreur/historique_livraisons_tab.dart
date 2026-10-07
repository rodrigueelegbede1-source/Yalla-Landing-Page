import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/widgets.dart';
import '../../l10n/app_localizations.dart';

class HistoriqueLivraisonsTab extends StatefulWidget {
  const HistoriqueLivraisonsTab({super.key, required this.cle});

  final int cle;

  @override
  State<HistoriqueLivraisonsTab> createState() =>
      _HistoriqueLivraisonsTabState();
}

class _HistoriqueLivraisonsTabState extends State<HistoriqueLivraisonsTab> {
  late Future<List<Map<String, dynamic>>> _livraisons;

  @override
  void initState() {
    super.initState();
    _livraisons = _charger();
  }

  @override
  void didUpdateWidget(HistoriqueLivraisonsTab ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.cle != widget.cle) _rafraichir();
  }

  Future<List<Map<String, dynamic>>> _charger() async {
    final lignes = await supabase
        .from('v_mes_courses')
        .select()
        .inFilter('statut_livraison', ['terminee', 'annulee'])
        .order('date_debut', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(lignes);
  }

  Future<void> _rafraichir() async {
    final f = _charger();
    if (mounted) setState(() => _livraisons = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();

    return RefreshIndicator(
      onRefresh: _rafraichir,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _livraisons,
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

          final livraisons = snap.data ?? const [];
          if (livraisons.isEmpty) {
            return EtatVide(
              icone: Icons.history,
              titre: l.historiqueLivraisonsVideTitre,
              message: l.historiqueLivraisonsVideMessage,
            );
          }

          return ListView.builder(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 24),
            itemCount: livraisons.length,
            itemBuilder: (context, index) {
              final livraison = livraisons[index];
              final terminee = livraison['statut_livraison'] == 'terminee';
              final date = DateTime.tryParse(
                livraison['date_debut']?.toString() ?? '',
              );
              final dateAffichee = date == null
                  ? ''
                  : DateFormat.yMd(locale).add_Hm().format(date.toLocal());
              final couleur = terminee ? Colors.green : Colors.blueGrey;

              return Card(
                margin: const EdgeInsetsDirectional.only(bottom: 10),
                child: ListTile(
                  leading: Icon(
                    terminee
                        ? Icons.check_circle_outline
                        : Icons.cancel_outlined,
                    color: couleur,
                  ),
                  title: Text(
                    livraison['produit_nom'] as String? ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      livraison['point_de_vente_nom'],
                      if (dateAffichee.isNotEmpty)
                        l.livraisonDemarreeLe(dateAffichee),
                    ].whereType<String>().join(' · '),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        terminee
                            ? l.livraisonTermineeHistorique
                            : l.livraisonAnnuleeHistorique,
                        style: TextStyle(
                          color: couleur,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (terminee && livraison['montant'] != null)
                        Text(
                          montant(context, livraison['montant'] as num),
                          style: const TextStyle(fontSize: 11),
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
