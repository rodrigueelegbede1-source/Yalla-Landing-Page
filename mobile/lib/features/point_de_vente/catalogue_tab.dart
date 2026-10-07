import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../core/vignette_produit.dart';
import '../../core/widgets.dart';
import '../../l10n/app_localizations.dart';

class CatalogueTab extends StatefulWidget {
  const CatalogueTab(
      {super.key, required this.cle, required this.onChangement});

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
    final future = _charger();
    if (mounted) setState(() => _catalogue = future);
    await future;
  }

  Future<void> _demander(Map<String, dynamic> produit) async {
    final l = L.of(context);
    final quantite = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
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
      if (mounted) _message(messageErreur(context, e));
    }
  }

  Future<void> _ouvrirFiche(Map<String, dynamic> produit) async {
    final demander = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FicheProduit(
        produit: produit,
        dejaDemande: produit['deja_demande'] == true,
        onDemander: () => Navigator.of(context).pop(true),
      ),
    );
    if (demander == true && mounted) await _demander(produit);
  }

  void _message(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texte)));
  }

  String _texteRecherche(Map<String, dynamic> produit) {
    final caracteristiques = produit['caracteristiques'];
    final valeursCaracteristiques =
        caracteristiques is Map ? caracteristiques.values.join(' ') : '';
    return [
      produit['produit_nom'],
      produit['fabricant_nom'],
      produit['reference'],
      produit['categorie_nom'],
      produit['format'],
      produit['description'],
      valeursCaracteristiques,
    ].whereType<Object>().join(' ').toLowerCase();
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

        final produits = tout.where((produit) {
          final image = produit['image_url'] as String?;
          return image != null && image.trim().isNotEmpty;
        }).toList();
        final sansImage = tout.length - produits.length;
        if (produits.isEmpty) {
          return EtatVide(
            icone: Icons.image_not_supported_outlined,
            titre: l.catalogueSansPhotoTitre,
            message: l.catalogueSansPhotoMessage,
          );
        }

        final categories = {
          for (final produit in produits)
            if ((produit['categorie_nom'] as String?)?.trim().isNotEmpty ==
                true)
              produit['categorie_nom'] as String,
        }.toList()
          ..sort();
        if (produits.any(
          (produit) =>
              (produit['categorie_nom'] as String?)?.trim().isNotEmpty != true,
        )) {
          categories.add(l.autresProduits);
          categories.sort();
        }

        final filtre = _filtre.trim().toLowerCase();
        final liste = produits.where((produit) {
          final nomCategorie = (produit['categorie_nom'] as String?)?.trim();
          final correspondCategorie = _categorie == null ||
              (_categorie == l.autresProduits
                  ? nomCategorie == null || nomCategorie.isEmpty
                  : nomCategorie == _categorie);
          if (!correspondCategorie) {
            return false;
          }
          return filtre.isEmpty || _texteRecherche(produit).contains(filtre);
        }).toList();

        final parCategorie = <String, List<Map<String, dynamic>>>{};
        for (final produit in liste) {
          final categorie = (produit['categorie_nom'] as String?)?.trim();
          parCategorie
              .putIfAbsent(
                categorie == null || categorie.isEmpty
                    ? l.autresProduits
                    : categorie,
                () => [],
              )
              .add(produit);
        }
        final sections = parCategorie.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        final nombreElements = liste.isEmpty
            ? 1
            : sections.fold<int>(
                0,
                (total, section) => total + 1 + section.value.length,
              );

        return Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.catalogueExplication,
                      style: const TextStyle(fontSize: 12, height: 1.4)),
                  if (sansImage > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      l.produitsSansImage(sansImage),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: l.rechercher,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (valeur) =>
                        setState(() => _filtre = valeur.toLowerCase()),
                  ),
                ],
              ),
            ),
            if (categories.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsetsDirectional.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(l.tousLesProduits),
                        selected: _categorie == null,
                        onSelected: (_) => setState(() => _categorie = null),
                      ),
                    ),
                    ...categories.map((categorie) => Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: ChoiceChip(
                            label: Text(categorie),
                            selected: _categorie == categorie,
                            onSelected: (_) => setState(() => _categorie =
                                _categorie == categorie ? null : categorie),
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
                  itemCount: nombreElements,
                  itemBuilder: (context, index) {
                    if (liste.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 56),
                        child: Center(child: Text(l.catalogueAucunResultat)),
                      );
                    }
                    var position = index;
                    for (final section in sections) {
                      if (position == 0) {
                        return Padding(
                          padding: const EdgeInsetsDirectional.only(
                            top: 8,
                            bottom: 4,
                          ),
                          child: TitreSection(
                            section.key,
                            detail: l.produitsCompteur(section.value.length),
                          ),
                        );
                      }
                      position--;
                      if (position < section.value.length) {
                        final produit = section.value[position];
                        return _CarteProduit(
                          produit: produit,
                          onOuvrir: () => _ouvrirFiche(produit),
                          onDemander: () => _demander(produit),
                        );
                      }
                      position -= section.value.length;
                    }
                    return const SizedBox.shrink();
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

class _CarteProduit extends StatelessWidget {
  const _CarteProduit({
    required this.produit,
    required this.onOuvrir,
    required this.onDemander,
  });

  final Map<String, dynamic> produit;
  final VoidCallback onOuvrir;
  final VoidCallback onDemander;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final demande = produit['deja_demande'] == true;
    final imageUrl = produit['image_url'] as String? ?? '';

    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOuvrir,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: Jetons.creme2,
                  child: Center(
                    child: Icon(Icons.broken_image_outlined, size: 34),
                  ),
                ),
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : ColoredBox(
                        color: Jetons.creme2,
                        child: Center(
                          child: CircularProgressIndicator(
                            value: progress.expectedTotalBytes == null
                                ? null
                                : progress.cumulativeBytesLoaded /
                                    progress.expectedTotalBytes!,
                          ),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((produit['format'] as String?)?.isNotEmpty == true)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.straighten, size: 15),
                        label: Text(produit['format'] as String),
                      ),
                    ),
                  Text(
                    produit['produit_nom'] as String? ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [produit['fabricant_nom'], produit['reference']]
                        .whereType<String>()
                        .where((valeur) => valeur.isNotEmpty)
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  if ((produit['description'] as String?)?.isNotEmpty ==
                      true) ...[
                    const SizedBox(height: 6),
                    Text(
                      produit['description'] as String,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, height: 1.35),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: onOuvrir,
                          icon: const Icon(Icons.info_outline, size: 18),
                          label: Text(l.voirDetails),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: demande
                            ? OutlinedButton(
                                onPressed: null,
                                child: Text(l.dejaDemande),
                              )
                            : FilledButton.tonal(
                                onPressed: onDemander,
                                style: boutonBoutDeLigne,
                                child: Text(l.demander),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FicheProduit extends StatelessWidget {
  const _FicheProduit({
    required this.produit,
    required this.dejaDemande,
    required this.onDemander,
  });

  final Map<String, dynamic> produit;
  final bool dejaDemande;
  final VoidCallback onDemander;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final caracteristiques = produit['caracteristiques'];
    final details = caracteristiques is Map
        ? caracteristiques.entries.toList()
        : const <MapEntry<String, dynamic>>[];
    final imageUrl = produit['image_url'] as String? ?? '';

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: .9,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 20),
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: Jetons.creme2,
                          child: Center(
                            child: Icon(Icons.broken_image_outlined, size: 44),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if ((produit['categorie_nom'] as String?)?.isNotEmpty == true)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Chip(
                        label: Text(produit['categorie_nom'] as String),
                      ),
                    ),
                  Text(
                    produit['produit_nom'] as String? ?? '',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    produit['fabricant_nom'] as String? ?? '',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Divider(height: 24),
                  _LigneDetailProduit(l.referenceProduit, produit['reference']),
                  _LigneDetailProduit(l.formatProduit, produit['format']),
                  _LigneDetailProduit(
                    l.descriptionProduit,
                    produit['description'],
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      l.caracteristiquesProduit,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    ...details.map(
                      (detail) => _LigneDetailProduit(
                        detail.key,
                        detail.value?.toString(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: dejaDemande
                    ? OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(l.dejaDemande),
                      )
                    : FilledButton.icon(
                        onPressed: onDemander,
                        icon: const Icon(Icons.add_shopping_cart),
                        label: Text(l.demander),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LigneDetailProduit extends StatelessWidget {
  const _LigneDetailProduit(this.libelle, this.valeur);

  final String libelle;
  final String? valeur;

  @override
  Widget build(BuildContext context) {
    if (valeur == null || valeur!.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              libelle,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(valeur!,
                style: const TextStyle(fontSize: 13, height: 1.4)),
          ),
        ],
      ),
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
  State<_ChoixQuantiteCatalogue> createState() =>
      _ChoixQuantiteCatalogueState();
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
                  child: Text(
                    widget.nom,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
                  child: Text(
                    '$_quantite',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
                  .map(
                    (nombre) => ChoiceChip(
                      label: Text('$nombre'),
                      selected: _quantite == nombre,
                      onSelected: (_) => setState(() => _quantite = nombre),
                    ),
                  )
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
