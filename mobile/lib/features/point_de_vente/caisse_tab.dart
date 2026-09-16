import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';

/// La caisse enregistreuse.
///
/// C'est le mécanisme le plus important du produit, et il est contre-intuitif :
/// **le boutiquier ne vient pas ici pour signaler une rupture**. Il vient pour
/// encaisser ses ventes, parce que ça lui rend service tous les jours. Le
/// signalement est un effet de bord, déclenché par un trigger quand une vente
/// vide un stock. C'est ce détour qui résout le vrai problème du produit : un
/// boutiquier n'a aucune raison spontanée de déclarer ses ruptures.
///
/// L'encaissement passe par `enregistrer_vente()`. Le total est recalculé en
/// base et non repris du panier : un montant envoyé depuis un téléphone peut
/// être n'importe quoi.
class CaisseTab extends StatefulWidget {
  const CaisseTab({super.key, required this.onVenteEnregistree});

  /// Appelé après un encaissement réussi, pour que l'onglet Stock se rafraîchisse :
  /// c'est là que la rupture éventuelle vient d'apparaître.
  final VoidCallback onVenteEnregistree;

  @override
  State<CaisseTab> createState() => _CaisseTabState();
}

class _CaisseTabState extends State<CaisseTab> {
  late Future<List<Map<String, dynamic>>> _catalogue;
  final List<_LignePanier> _panier = [];
  bool _encaissement = false;

  @override
  void initState() {
    super.initState();
    _catalogue = _chargerCatalogue();
  }

  /// Le catalogue proposé est celui du stock suivi de la boutique, pas le
  /// catalogue global : on vend ce qu'on a en rayon. Un produit hors catalogue
  /// s'ajoute à la main.
  Future<List<Map<String, dynamic>>> _chargerCatalogue() async {
    final lignes = await supabase
        .from('v_stock_point_de_vente')
        .select('produit_id, produit_nom, quantite, fabricant_nom')
        .not('produit_id', 'is', null)
        .order('produit_nom');
    return List<Map<String, dynamic>>.from(lignes);
  }

  num get _total => _panier.fold<num>(0, (s, l) => s + l.quantite * l.prixUnitaire);

  void _ajouter(Map<String, dynamic> produit) async {
    final prix = await _demanderPrix(produit['produit_nom'] as String? ?? 'Produit');
    if (prix == null || !mounted) return;

    setState(() {
      final existante = _panier.indexWhere((l) => l.produitId == produit['produit_id']);
      if (existante >= 0) {
        _panier[existante].quantite++;
      } else {
        _panier.add(_LignePanier(
          produitId: produit['produit_id'] as String?,
          nom: produit['produit_nom'] as String? ?? 'Produit',
          prixUnitaire: prix,
        ));
      }
    });
  }

  Future<num?> _demanderPrix(String nom) async {
    final controleur = TextEditingController();
    return showDialog<num>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(nom),
        content: TextField(
          controller: controleur,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Prix unitaire',
            suffixText: 'F',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(context, num.tryParse(controleur.text)),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  Future<void> _ajouterHorsCatalogue() async {
    final nomCtrl = TextEditingController();
    final prixCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Produit hors catalogue'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nomCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nom du produit',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: prixCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Prix unitaire',
                suffixText: 'F',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ajouter')),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    final prix = num.tryParse(prixCtrl.text);
    if (nomCtrl.text.trim().isEmpty || prix == null) return;

    // produitId nul : la vente est enregistrée, mais elle ne touche ni les
    // stocks ni les ruptures. C'est prévu par le schéma depuis l'origine, une
    // boutique vend forcément des choses hors du catalogue Yalla.
    setState(() => _panier.add(_LignePanier(
          produitId: null,
          nom: nomCtrl.text.trim(),
          prixUnitaire: prix,
        )));
  }

  Future<void> _encaisser() async {
    if (_panier.isEmpty) return;
    setState(() => _encaissement = true);

    try {
      await supabase.rpc('enregistrer_vente', params: {
        'p_lignes': _panier
            .map((l) => {
                  if (l.produitId != null) 'produit_id': l.produitId,
                  if (l.produitId == null) 'produit_libre_nom': l.nom,
                  'quantite': l.quantite,
                  'prix_unitaire': l.prixUnitaire,
                })
            .toList(),
      });

      if (!mounted) return;
      final total = _total;
      setState(() => _panier.clear());
      _catalogue = _chargerCatalogue();
      widget.onVenteEnregistree();
      _message('Vente de ${montant(total)} encaissée');
    } catch (e) {
      _message(messageErreur(e));
    } finally {
      if (mounted) setState(() => _encaissement = false);
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
    return Column(
      children: [
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _catalogue,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text(messageErreur(snap.error!)));
              }

              final produits = snap.data ?? const [];
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_panier.isNotEmpty) ...[
                    const Text('Panier',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 8),
                    ..._panier.asMap().entries.map((e) => _LigneCard(
                          ligne: e.value,
                          onMoins: () => setState(() {
                            if (e.value.quantite > 1) {
                              e.value.quantite--;
                            } else {
                              _panier.removeAt(e.key);
                            }
                          }),
                          onPlus: () => setState(() => e.value.quantite++),
                        )),
                    const Divider(height: 32),
                  ],
                  const Text('Ajouter au panier',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 8),
                  if (produits.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Aucun produit suivi. Ajoutez du stock depuis l\'onglet Stock '
                        'pour que Yalla détecte vos ruptures automatiquement.',
                        style: TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ...produits.map((p) {
                    final q = (p['quantite'] as num?)?.toInt() ?? 0;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        q > 0 ? Icons.add_shopping_cart : Icons.remove_shopping_cart_outlined,
                        color: q > 0 ? null : Colors.red,
                      ),
                      title: Text(p['produit_nom'] as String? ?? ''),
                      subtitle: Text(q > 0 ? '$q en stock' : 'Rupture'),
                      enabled: q > 0,
                      onTap: q > 0 ? () => _ajouter(p) : null,
                    );
                  }),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Produit hors catalogue'),
                    onPressed: _ajouterHorsCatalogue,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Chaque vente qui met un stock à zéro prévient votre '
                    'distributeur toute seule. Vous n\'avez rien à signaler.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                ],
              );
            },
          ),
        ),
        if (_panier.isNotEmpty)
          Material(
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total', style: TextStyle(fontSize: 12)),
                        Text(montant(_total),
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: _encaissement ? null : _encaisser,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                    child: _encaissement
                        ? const SizedBox(
                            height: 20, width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Encaisser'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _LignePanier {
  _LignePanier({required this.produitId, required this.nom, required this.prixUnitaire});
  final String? produitId;
  final String nom;
  final num prixUnitaire;
  int quantite = 1;
}

class _LigneCard extends StatelessWidget {
  const _LigneCard({required this.ligne, required this.onMoins, required this.onPlus});
  final _LignePanier ligne;
  final VoidCallback onMoins;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ligne.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${montant(ligne.prixUnitaire)} l\'unité',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: onMoins),
            Text('${ligne.quantite}', style: const TextStyle(fontWeight: FontWeight.w700)),
            IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: onPlus),
            SizedBox(
              width: 80,
              child: Text(montant(ligne.quantite * ligne.prixUnitaire),
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}
