import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/vignette_produit.dart';
import '../../l10n/app_localizations.dart';
import '../../core/supabase.dart';

/// Stock de la boutique, et signalement manuel.
///
/// L'alimentation du stock n'est pas un confort : **sans ligne de stock suivie,
/// le trigger de caisse sort sans rien faire et aucune rupture automatique ne
/// peut naître**. C'est l'écran qui rend le mécanisme central opérant, et
/// l'ancien backend ne l'avait tout simplement pas.
///
/// Le bouton « Signaler » reste le filet. En régime normal, le boutiquier ne
/// s'en sert pas : la vente qui vide le rayon a déjà prévenu son distributeur.
class StockTab extends StatefulWidget {
  const StockTab({super.key, required this.pointDeVenteId, required this.cle});

  final String pointDeVenteId;

  /// Change quand une vente vient d'être encaissée, pour forcer le rechargement :
  /// c'est à ce moment qu'une rupture a pu apparaître.
  final int cle;

  @override
  State<StockTab> createState() => _StockTabState();
}

class _StockTabState extends State<StockTab> {
  late Future<_Donnees> _donnees;

  @override
  void initState() {
    super.initState();
    _donnees = _charger();
  }

  @override
  void didUpdateWidget(StockTab ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.cle != widget.cle) _rafraichir();
  }

  Future<_Donnees> _charger() async {
    final r = await Future.wait([
      supabase.from('v_stock_point_de_vente').select().order('produit_nom'),
      supabase
          .from('ruptures')
          .select('id, produit_id, statut, date_signalement')
          .inFilter('statut', ['signalee', 'prise_en_charge']),
      supabase.from('produits').select('id, nom, reference, fabricants(nom)').order('nom'),
    ]);
    return _Donnees(
      stock: List<Map<String, dynamic>>.from(r[0]),
      ruptures: List<Map<String, dynamic>>.from(r[1]),
      catalogue: List<Map<String, dynamic>>.from(r[2]),
    );
  }

  Future<void> _rafraichir() async {
    final f = _charger();
    if (mounted) setState(() => _donnees = f);
    await f;
  }

  Future<void> _reapprovisionner(String produitId, String nom, int actuel) async {
    final l = L.of(context);
    final variation = await _demanderNombre(
      titre: nom,
      question: l.combienUnitesRecues,
      suffixe: 'unité(s)',
      valeurInitiale: '',
    );
    if (variation == null) return;

    try {
      await supabase.rpc('reapprovisionner_stock',
          params: {'p_produit_id': produitId, 'p_quantite': variation});
      _message(l.stockMisAJour('${actuel + variation}'));
    } catch (e) {
      if (!mounted) return;
      _message(messageErreur(context, e));
    }
    await _rafraichir();
  }

  Future<void> _signaler(String produitId, String nom) async {
    final l = L.of(context);
    final quantite = await _demanderNombre(
      titre: nom,
      question: l.combienDeCartons,
      suffixe: 'carton(s)',
      valeurInitiale: '1',
    );
    if (quantite == null) return;

    try {
      // Le destinataire n'est pas choisi ici : un trigger le résout à
      // l'insertion, exactement comme pour une rupture née de la caisse.
      await supabase.from('ruptures').insert({
        'point_de_vente_id': widget.pointDeVenteId,
        'produit_id': produitId,
        'quantite_demandee': quantite,
        'signalement_automatique': false,
      });
      _message(l.ruptureTransmise);
    } catch (e) {
      if (!mounted) return;
      _message(messageErreur(context, e));
    }
    await _rafraichir();
  }

  Future<void> _ajouterAuSuivi(List<Map<String, dynamic>> catalogue, Set<String> dejaSuivis) async {
    final l = L.of(context);
    final disponibles = catalogue.where((p) => !dejaSuivis.contains(p['id'])).toList();
    if (disponibles.isEmpty) {
      _message(l.tousDejaSuivis);
      return;
    }

    final choix = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, controleur) => ListView(
          controller: controleur,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Suivre un produit',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ...disponibles.map((p) => ListTile(
                  title: Text(p['nom'] as String? ?? ''),
                  subtitle: Text([
                    (p['fabricants'] as Map?)?['nom'],
                    p['reference'],
                  ].whereType<String>().join(' · ')),
                  onTap: () => Navigator.pop(context, p),
                )),
          ],
        ),
      ),
    );

    if (choix == null || !mounted) return;
    await _reapprovisionner(choix['id'] as String, choix['nom'] as String? ?? '', 0);
  }

  Future<int?> _demanderNombre({
    required String titre,
    required String question,
    required String suffixe,
    required String valeurInitiale,
  }) {
    final controleur = TextEditingController(text: valeurInitiale);
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titre),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(question),
            const SizedBox(height: 12),
            TextField(
              controller: controleur,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                suffixText: suffixe,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controleur.text);
              Navigator.pop(context, (v == null || v <= 0) ? null : v);
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  void _message(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texte)));
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return RefreshIndicator(
      onRefresh: _rafraichir,
      child: FutureBuilder<_Donnees>(
        future: _donnees,
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

          final d = snap.data!;
          final signales =
              d.ruptures.map((r) => r['produit_id'] as String?).whereType<String>().toSet();
          final suivis =
              d.stock.map((s) => s['produit_id'] as String?).whereType<String>().toSet();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (d.ruptures.isNotEmpty)
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '${d.ruptures.length} rupture(s) en cours de traitement chez '
                      'votre distributeur. Rien d\'autre à faire de votre côté.',
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l.monStock,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l.suivreUnProduit),
                    onPressed: () => _ajouterAuSuivi(d.catalogue, suivis),
                  ),
                ],
              ),
              if (d.stock.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    l.stockVideMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
              ...d.stock.map((s) {
                final produitId = s['produit_id'] as String?;
                final nom = s['produit_nom'] as String? ?? 'Produit';
                final q = (s['quantite'] as num?)?.toInt() ?? 0;
                final vide = s['en_rupture'] == true;
                final dejaSignale = produitId != null && signales.contains(produitId);

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: VignetteProduit(
                      nom: nom,
                      imageUrl: s['image_url'] as String?,
                      categorie: s['categorie_nom'] as String?,
                      taille: 44,
                    ),
                    title: Text(nom),
                    subtitle: Text([
                      '$q en stock',
                      if (s['fabricant_nom'] != null) s['fabricant_nom'] as String,
                    ].join(' · ')),
                    trailing: produitId == null
                        ? null
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.add_box_outlined),
                                tooltip: l.reapprovisionner,
                                onPressed: () => _reapprovisionner(produitId, nom, q),
                              ),
                              if (dejaSignale)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Text(l.signale, style: const TextStyle(fontSize: 12)),
                                )
                              else if (vide)
                                TextButton(
                                  onPressed: () => _signaler(produitId, nom),
                                  child: Text(l.signaler),
                                ),
                            ],
                          ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              Text(
                l.confidentialite,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Donnees {
  const _Donnees({required this.stock, required this.ruptures, required this.catalogue});
  final List<Map<String, dynamic>> stock;
  final List<Map<String, dynamic>> ruptures;
  final List<Map<String, dynamic>> catalogue;
}
