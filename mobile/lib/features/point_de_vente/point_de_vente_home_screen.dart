import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/format.dart';
import '../../core/supabase.dart';

/// Écran du point de vente : son stock, et le signalement d'une rupture.
///
/// La caisse complète, avec panier et encaissement, reste à construire. Elle
/// est le morceau le plus lourd du MVP et mérite son propre chantier.
///
/// Ce qu'il faut retenir en lisant cet écran : **le boutiquier n'a normalement
/// rien à signaler**. Quand la caisse sera là, une vente qui vide un stock
/// déclenchera la rupture toute seule, par un trigger en base. Le bouton de
/// signalement manuel est le filet, pas le mécanisme principal.
///
/// Ses données sont privées : les politiques RLS ne laissent ni le distributeur
/// ni le fabricant lire ses stocks ou ses ventes. C'est ce qui rend la caisse
/// gratuite acceptable, et donc ce qui fait fonctionner le signalement automatique.
class PointDeVenteHomeScreen extends ConsumerStatefulWidget {
  const PointDeVenteHomeScreen({super.key, required this.pointDeVenteId});

  final String pointDeVenteId;

  @override
  ConsumerState<PointDeVenteHomeScreen> createState() => _PointDeVenteHomeScreenState();
}

class _PointDeVenteHomeScreenState extends ConsumerState<PointDeVenteHomeScreen> {
  late Future<_Donnees> _donnees;

  @override
  void initState() {
    super.initState();
    _donnees = _charger();
  }

  Future<_Donnees> _charger() async {
    // Deux requêtes indépendantes, lancées ensemble plutôt qu'à la suite.
    final resultats = await Future.wait([
      supabase.from('v_stock_point_de_vente').select().order('produit_nom'),
      supabase
          .from('ruptures')
          .select('id, produit_id, statut, date_signalement, signalement_automatique')
          .inFilter('statut', ['signalee', 'prise_en_charge'])
          .order('date_signalement', ascending: false),
    ]);

    return _Donnees(
      stock: List<Map<String, dynamic>>.from(resultats[0]),
      ruptures: List<Map<String, dynamic>>.from(resultats[1]),
    );
  }

  Future<void> _rafraichir() async {
    final f = _charger();
    setState(() => _donnees = f);
    await f;
  }

  Future<void> _signaler(String produitId, String produitNom) async {
    final quantite = await _demanderQuantite(produitNom);
    if (quantite == null) return;

    try {
      // Le destinataire n'est pas choisi ici : un trigger en base le résout à
      // l'insertion, exactement comme pour une rupture née de la caisse.
      await supabase.from('ruptures').insert({
        'point_de_vente_id': widget.pointDeVenteId,
        'produit_id': produitId,
        'quantite_demandee': quantite,
        'signalement_automatique': false,
      });
      _message('Rupture signalée à votre distributeur');
    } catch (e) {
      _message(messageErreur(e));
    }
    await _rafraichir();
  }

  Future<int?> _demanderQuantite(String produitNom) async {
    final controleur = TextEditingController(text: '1');
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(produitNom),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Combien de cartons vous faut-il ?'),
            const SizedBox(height: 12),
            TextField(
              controller: controleur,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                suffixText: 'carton(s)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(controleur.text) ?? 1),
            child: const Text('Signaler'),
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
    final session = ref.watch(sessionProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(session?.nom ?? 'Ma boutique'),
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
        child: FutureBuilder<_Donnees>(
          future: _donnees,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _Message(
                icone: Icons.cloud_off_outlined,
                titre: 'Chargement impossible',
                texte: messageErreur(snap.error!),
              );
            }

            final d = snap.data!;
            if (d.stock.isEmpty) {
              return const _Message(
                icone: Icons.inventory_2_outlined,
                titre: 'Aucun produit suivi',
                texte: 'Votre distributeur n\'a pas encore rattaché de produit à '
                    'votre boutique. Sans stock suivi, Yalla ne peut pas détecter '
                    'vos ruptures automatiquement.',
              );
            }

            final produitsEnRupture =
                d.ruptures.map((r) => r['produit_id'] as String?).whereType<String>().toSet();

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (d.ruptures.isNotEmpty) ...[
                  _Titre('En cours de réapprovisionnement', '${d.ruptures.length}'),
                  Card(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '${d.ruptures.length} rupture(s) transmise(s) à votre '
                        'distributeur. Vous n\'avez rien d\'autre à faire.',
                        style: const TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                _Titre('Mon stock', '${d.stock.length} produit(s)'),
                ...d.stock.map((s) {
                  final produitId = s['produit_id'] as String?;
                  final nom = s['produit_nom'] as String? ?? 'Produit';
                  final quantite = (s['quantite'] as num?)?.toInt() ?? 0;
                  final dejaSignale = produitId != null && produitsEnRupture.contains(produitId);
                  final vide = s['en_rupture'] == true;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        vide ? Icons.error_outline : Icons.inventory_2_outlined,
                        color: vide ? Colors.red : null,
                      ),
                      title: Text(nom),
                      subtitle: Text(
                        '$quantite en stock'
                        '${s['fabricant_nom'] != null ? ' · ${s['fabricant_nom']}' : ''}',
                      ),
                      trailing: dejaSignale
                          ? const Text('Signalé', style: TextStyle(fontSize: 12))
                          : produitId == null
                              ? null
                              : TextButton(
                                  onPressed: () => _signaler(produitId, nom),
                                  child: const Text('Signaler'),
                                ),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                const Text(
                  'Vos ventes et vos stocks ne sont visibles que de vous. '
                  'Ni votre distributeur, ni les fabricants n\'y ont accès.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Donnees {
  const _Donnees({required this.stock, required this.ruptures});
  final List<Map<String, dynamic>> stock;
  final List<Map<String, dynamic>> ruptures;
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

class _Message extends StatelessWidget {
  const _Message({required this.icone, required this.titre, required this.texte});
  final IconData icone;
  final String titre;
  final String texte;

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
            child: Text(texte,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, height: 1.5)),
          ),
        ],
      );
}
