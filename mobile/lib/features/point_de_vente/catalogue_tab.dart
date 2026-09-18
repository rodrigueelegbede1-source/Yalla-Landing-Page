import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/vignette_produit.dart';
import '../../core/widgets.dart';
import '../../l10n/app_localizations.dart';

/// Le catalogue des fabricants qui desservent la boutique, pour demander un
/// produit sans passer par la caisse.
///
/// POURQUOI CET ÉCRAN EST INDISPENSABLE, et pas un supplément de confort. La
/// caisse est le mécanisme le plus élégant du produit, mais elle repose sur une
/// hypothèse forte : que le boutiquier l'utilise. Beaucoup tiendront leurs
/// comptes sur un cahier, comme ils le font depuis toujours, et n'ouvriront la
/// caisse jamais. Sans ce catalogue, ceux-là ne peuvent rien demander, et Yalla
/// ne leur sert à rien.
///
/// Il couvre aussi un cas que la caisse ne peut pas atteindre : demander un
/// produit qu'on ne suit pas en stock, voire qu'on n'a jamais vendu. Un
/// boutiquier qui veut essayer une référence nouvelle passe forcément par là.
///
/// LES IMAGES ONT ICI LEUR PLUS GRANDE UTILITÉ. Choisir dans une liste de
/// trente références en texte seul est lent et source d'erreur. Une vignette,
/// même sans photo, donne la catégorie par sa couleur et le produit par ses
/// initiales, ce qui suffit à repérer sans lire.
class CatalogueTab extends StatefulWidget {
  const CatalogueTab({super.key, required this.cle, required this.onChangement});

  final int cle;
  final VoidCallback onChangement;

  @override
  State<CatalogueTab> createState() => _CatalogueTabState();
}

class _CatalogueTabState extends State<CatalogueTab> {
  late Future<List<Map<String, dynamic>>> _catalogue;
  String _filtre = '';
  String? _categorie;

  @override
  void initState() {
    super.initState();
    _catalogue = _charger();
  }

  @override
  void didUpdateWidget(CatalogueTab ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.cle != widget.cle) _rafraichir();
  }

  Future<List<Map<String, dynamic>>> _charger() async {
    final lignes = await supabase
        .from('v_catalogue_point_de_vente')
        .select()
        .order('fabricant_nom')
        .order('produit_nom');
    return List<Map<String, dynamic>>.from(lignes);
  }

  Future<void> _rafraichir() async {
    final f = _charger();
    if (mounted) setState(() => _catalogue = f);
    await f;
  }

  Future<void> _demander(Map<String, dynamic> produit) async {
    final l = L.of(context);
    final quantite = await showModalBottomSheet<int>(
      context: context,
      builder: (_) => _ChoixQuantiteCatalogue(
        nom: produit['produit_nom'] as String? ?? '',
        imageUrl: produit['image_url'] as String?,
        categorie: produit['categorie_nom'] as String?,
      ),
    );
    if (quantite == null || !mounted) return;

    try {
      await supabase.rpc('signaler_rupture', params: {
        'p_produit_id': produit['produit_id'],
        'p_quantite': quantite,
      });
      _message(l.demandeEnvoyee);
      widget.onChangement();
      await _rafraichir();
    } catch (e) {
      if (!mounted) return;
      _message(messageErreur(context, e));
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
    final l = L.of(context);

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _catalogue,
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

        final tout = snap.data ?? const <Map<String, dynamic>>[];
        if (tout.isEmpty) {
          return EtatVide(
            icone: Icons.inventory_2_outlined,
            titre: l.catalogueVideTitre,
            message: l.catalogueVideMessage,
          );
        }

        final categories = {
          for (final p in tout)
            if (p['categorie_nom'] != null) p['categorie_nom'] as String
        }.toList()
          ..sort();

        final liste = tout.where((p) {
          if (_categorie != null && p['categorie_nom'] != _categorie) return false;
          if (_filtre.isEmpty) return true;
          final texte =
              '${p['produit_nom']} ${p['fabricant_nom']} ${p['reference']}'
                  .toLowerCase();
          return texte.contains(_filtre);
        }).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.catalogueExplication,
                      style: const TextStyle(fontSize: 12, height: 1.4)),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: l.rechercher,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _filtre = v.toLowerCase()),
                  ),
                ],
              ),
            ),
            if (categories.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(l.tousLesProduits),
                        selected: _categorie == null,
                        onSelected: (_) => setState(() => _categorie = null),
                      ),
                    ),
                    ...categories.map((c) => Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: ChoiceChip(
                            label: Text(c),
                            selected: _categorie == c,
                            onSelected: (_) => setState(
                                () => _categorie = _categorie == c ? null : c),
                          ),
                        )),
                  ],
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _rafraichir,
                child: ListView.builder(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 24),
                  itemCount: liste.length,
                  itemBuilder: (context, i) {
                    final p = liste[i];
                    final demande = p['deja_demande'] == true;
                    final stock = (p['quantite_en_stock'] as num?)?.toInt();

                    return Card(
                      margin: const EdgeInsetsDirectional.only(bottom: 8),
                      child: ListTile(
                        contentPadding:
                            const EdgeInsetsDirectional.fromSTEB(12, 6, 8, 6),
                        leading: VignetteProduit(
                          nom: p['produit_nom'] as String? ?? '',
                          imageUrl: p['image_url'] as String?,
                          categorie: p['categorie_nom'] as String?,
                          taille: 46,
                        ),
                        title: Text(p['produit_nom'] as String? ?? '',
                            style: const TextStyle(fontSize: 14)),
                        subtitle: Text(
                          [
                            p['fabricant_nom'],
                            if (stock != null && stock > 0) l.enStock(stock),
                          ].where((e) => e != null).join(' · '),
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        trailing: demande
                            ? Text(l.dejaDemande,
                                style: const TextStyle(fontSize: 11))
                            : FilledButton.tonal(
                                onPressed: () => _demander(p),
                                child: Text(l.demander),
                              ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ChoixQuantiteCatalogue extends StatefulWidget {
  const _ChoixQuantiteCatalogue({
    required this.nom,
    this.imageUrl,
    this.categorie,
  });

  final String nom;
  final String? imageUrl;
  final String? categorie;

  @override
  State<_ChoixQuantiteCatalogue> createState() => _ChoixQuantiteCatalogueState();
}

class _ChoixQuantiteCatalogueState extends State<_ChoixQuantiteCatalogue> {
  int _quantite = 1;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                VignetteProduit(
                  nom: widget.nom,
                  imageUrl: widget.imageUrl,
                  categorie: widget.categorie,
                  taille: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(widget.nom,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(l.combienDeCartons, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  onPressed:
                      _quantite > 1 ? () => setState(() => _quantite--) : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 96,
                  child: Text('$_quantite',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 34, fontWeight: FontWeight.w700)),
                ),
                IconButton.filledTonal(
                  onPressed: () => setState(() => _quantite++),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [1, 2, 5, 10, 20]
                  .map((n) => ChoiceChip(
                        label: Text('$n'),
                        selected: _quantite == n,
                        onSelected: (_) => setState(() => _quantite = n),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context, _quantite),
              child: Text(l.demander),
            ),
          ],
        ),
      ),
    );
  }
}
