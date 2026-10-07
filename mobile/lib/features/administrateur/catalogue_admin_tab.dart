import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/import_catalogue_dialog.dart';
import '../../core/supabase.dart';
import '../../core/vignette_produit.dart';
import '../../core/widgets.dart';

class CatalogueAdminTab extends StatefulWidget {
  const CatalogueAdminTab({super.key});

  @override
  State<CatalogueAdminTab> createState() => _CatalogueAdminTabState();
}

class _CatalogueAdminTabState extends State<CatalogueAdminTab> {
  late Future<_CatalogueAdmin> _donnees;

  @override
  void initState() {
    super.initState();
    _donnees = _charger();
  }

  Future<_CatalogueAdmin> _charger() async {
    final resultats = await Future.wait<Object?>([
      supabase
          .from('produits')
          .select('id, nom, reference, image_url, disponible, fabricants(nom)')
          .order('nom'),
      supabase.from('fabricants').select('id, nom').order('nom'),
      supabase
          .from('demandes_catalogue_pdf')
          .select(
              'id, fabricant_id, fichier_pdf, statut, created_at, fabricants(nom)')
          .order('created_at', ascending: false)
          .limit(50),
    ]);
    return _CatalogueAdmin(
      produits: List<Map<String, dynamic>>.from(resultats[0] as List),
      fabricants: List<Map<String, dynamic>>.from(resultats[1] as List),
      demandesPdf: List<Map<String, dynamic>>.from(resultats[2] as List),
    );
  }

  Future<void> _rafraichir() async {
    final future = _charger();
    if (mounted) setState(() => _donnees = future);
    await future;
  }

  Future<void> _importer(List<Map<String, dynamic>> fabricants) async {
    final resultat = await ouvrirImportCatalogue(context, marques: fabricants);
    if (resultat == true && mounted) await _rafraichir();
  }

  Future<void> _ouvrirPdf(Map<String, dynamic> demande) async {
    try {
      final url = await supabase.storage
          .from('catalogue-imports')
          .createSignedUrl(demande['fichier_pdf'] as String, 300);
      final ouvert = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ouvert && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d’ouvrir le PDF.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('PDF indisponible : ${messageErreur(context, e)}')),
      );
    }
  }

  Future<void> _changerStatutPdf(
    Map<String, dynamic> demande,
    String statut,
  ) async {
    final marque = demande['fabricants'] as Map<String, dynamic>?;
    final nom = marque?['nom'] as String? ?? 'ce catalogue';
    if (statut == 'traitee') {
      final confirme = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Clôturer le traitement ?'),
          content: Text(
            'Confirmez que les références de $nom ont été importées depuis un fichier structuré.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      );
      if (confirme != true) return;
    }

    try {
      await supabase.rpc('changer_statut_demande_catalogue_pdf', params: {
        'p_demande_id': demande['id'],
        'p_statut': statut,
        'p_note': null,
      });
      await _rafraichir();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageErreur(context, e))),
      );
    }
  }

  Future<void> _importerDepuisPdf(
    Map<String, dynamic> demande,
    List<Map<String, dynamic>> fabricants,
  ) async {
    final importe = await ouvrirImportCatalogue(
      context,
      marques: fabricants,
      fabricantInitial: demande['fabricant_id'] as String,
    );
    if (importe != true || !mounted) return;
    try {
      await supabase.rpc('changer_statut_demande_catalogue_pdf', params: {
        'p_demande_id': demande['id'],
        'p_statut': 'traitee',
        'p_note': 'Catalogue importé depuis le document source.',
      });
      await _rafraichir();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Produits importés, mais la demande PDF reste à clôturer : ${messageErreur(context, e)}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _rafraichir,
        child: FutureBuilder<_CatalogueAdmin>(
          future: _donnees,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return EtatVide(
                icone: Icons.cloud_off_outlined,
                titre: 'Catalogue indisponible',
                message: messageErreur(context, snap.error!),
              );
            }

            final donnees = snap.data!;
            return ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
              children: [
                TitreSection(
                  'Catalogue réseau',
                  detail: '${donnees.produits.length} références',
                ),
                FilledButton.icon(
                  onPressed: donnees.fabricants.isEmpty
                      ? null
                      : () => _importer(donnees.fabricants),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Importer par fichier'),
                ),
                const SizedBox(height: 12),
                TitreSection(
                  'PDF à traiter',
                  detail:
                      '${donnees.demandesPdf.where((d) => d['statut'] != 'traitee' && d['statut'] != 'refusee').length} en attente',
                ),
                const Padding(
                  padding: EdgeInsetsDirectional.only(bottom: 8),
                  child: Text(
                    'Ouvrez le document privé, préparez un fichier Excel/CSV et son ZIP d’images, puis importez les références avant de clôturer.',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
                if (donnees.demandesPdf.isEmpty)
                  const Padding(
                    padding: EdgeInsetsDirectional.only(bottom: 12),
                    child: Text('Aucun PDF transmis.'),
                  )
                else
                  ...donnees.demandesPdf.map((demande) {
                    final marque =
                        demande['fabricants'] as Map<String, dynamic>?;
                    final statut = demande['statut'] as String? ?? 'en_attente';
                    final date =
                        DateTime.tryParse('${demande['created_at'] ?? ''}')
                            ?.toLocal();
                    final dateTexte =
                        date == null ? '' : date.toString().substring(0, 16);
                    return Card(
                      margin: const EdgeInsetsDirectional.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading:
                                  const Icon(Icons.picture_as_pdf_outlined),
                              title:
                                  Text(marque?['nom'] as String? ?? 'Marque'),
                              subtitle: Text(
                                  '$statut${dateTexte.isEmpty ? '' : ' · $dateTexte'}'),
                              trailing: IconButton(
                                tooltip: 'Ouvrir le PDF privé',
                                onPressed: () => _ouvrirPdf(demande),
                                icon: const Icon(Icons.open_in_new),
                              ),
                            ),
                            if (statut == 'en_attente')
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _changerStatutPdf(demande, 'en_cours'),
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Prendre en charge'),
                              ),
                            if (statut == 'en_cours') ...[
                              OutlinedButton.icon(
                                onPressed: () => _importerDepuisPdf(
                                    demande, donnees.fabricants),
                                icon: const Icon(Icons.upload_file),
                                label: const Text('Importer les références'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    _changerStatutPdf(demande, 'refusee'),
                                child: const Text('Refuser le document'),
                              ),
                            ],
                            if (statut == 'traitee' || statut == 'refusee')
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(
                                  statut == 'traitee'
                                      ? 'Traitement terminé'
                                      : 'Document refusé',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 8),
                if (donnees.produits.isEmpty)
                  const EtatVide(
                    icone: Icons.inventory_2_outlined,
                    titre: 'Aucune référence',
                    message: 'Importez le catalogue d’une marque existante.',
                  )
                else
                  ...donnees.produits.map((produit) {
                    final fabricant =
                        produit['fabricants'] as Map<String, dynamic>?;
                    return Card(
                      margin: const EdgeInsetsDirectional.only(bottom: 8),
                      child: ListTile(
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
                        subtitle: Text(
                          '${fabricant?['nom'] ?? ''} · ${produit['reference'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Icon(
                          produit['image_url'] == null
                              ? Icons.image_not_supported_outlined
                              : Icons.image_outlined,
                        ),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      );
}

class _CatalogueAdmin {
  const _CatalogueAdmin({
    required this.produits,
    required this.fabricants,
    required this.demandesPdf,
  });

  final List<Map<String, dynamic>> produits;
  final List<Map<String, dynamic>> fabricants;
  final List<Map<String, dynamic>> demandesPdf;
}
