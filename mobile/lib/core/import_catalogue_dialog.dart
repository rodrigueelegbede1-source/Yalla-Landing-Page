import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase.dart';

Future<bool?> ouvrirImportCatalogue(
  BuildContext context, {
  required List<Map<String, dynamic>> marques,
  String? fabricantInitial,
}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => _ImportCatalogueDialog(
        marques: marques,
        fabricantInitial: fabricantInitial,
      ),
    );

class _LigneCatalogue {
  const _LigneCatalogue({
    required this.reference,
    required this.nom,
    required this.categorie,
    required this.format,
    required this.description,
    required this.caracteristiques,
  });

  final String reference;
  final String nom;
  final String categorie;
  final String format;
  final String description;
  final Map<String, dynamic> caracteristiques;

  Map<String, dynamic> versJson(String imageUrl) => {
        'reference': reference,
        'nom': nom,
        'categorie': categorie,
        'format': format,
        'description': description,
        'caracteristiques': caracteristiques,
        'image_url': imageUrl,
      };
}

class _ImportCatalogueDialog extends StatefulWidget {
  const _ImportCatalogueDialog({
    required this.marques,
    this.fabricantInitial,
  });

  final List<Map<String, dynamic>> marques;
  final String? fabricantInitial;

  @override
  State<_ImportCatalogueDialog> createState() => _ImportCatalogueDialogState();
}

class _ImportCatalogueDialogState extends State<_ImportCatalogueDialog> {
  static const _limiteTableur = 20 * 1024 * 1024;
  static const _limiteZip = 20 * 1024 * 1024;
  static const _limiteImage = 5 * 1024 * 1024;
  static const _limitePhotosDecompressees = 80 * 1024 * 1024;
  static const _extensionsImage = {'jpg', 'jpeg', 'png', 'webp'};

  String? _fabricantId;
  String? _nomTableur;
  String? _nomZip;
  String? _nomPdf;
  String? _erreur;
  bool _occupe = false;
  bool _pdfSeul = false;
  List<int>? _tableur;
  List<int>? _zip;
  List<int>? _pdf;
  List<_LigneCatalogue> _lignes = [];
  Map<String, List<int>> _images = {};

  @override
  void initState() {
    super.initState();
    _fabricantId = widget.fabricantInitial;
  }

  String _extension(String nom) =>
      nom.contains('.') ? nom.split('.').last.toLowerCase() : '';

  Future<void> _choisirTableur() async {
    final resultat = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx'],
      withData: true,
    );
    if (resultat == null || !mounted) return;
    final fichier = resultat.files.single;
    final octets = fichier.bytes;
    if (octets == null || octets.isEmpty || octets.length > _limiteTableur) {
      setState(() => _erreur = 'Fichier vide ou supérieur à 20 Mo.');
      return;
    }

    try {
      final donnees = _extension(fichier.name) == 'csv'
          ? _lireCsv(octets)
          : _lireExcel(octets);
      final lignes = _lireLignes(donnees);
      setState(() {
        _nomTableur = fichier.name;
        _tableur = octets;
        _lignes = lignes;
        _erreur = null;
      });
    } catch (e) {
      setState(() => _erreur = 'Lecture impossible : $e');
    }
  }

  List<List<String>> _lireCsv(List<int> octets) {
    final texte =
        utf8.decode(octets, allowMalformed: false).replaceFirst('\uFEFF', '');
    final premiereLigne = texte.split(RegExp(r'\r?\n')).first;
    final delimiteur = premiereLigne.contains(';') ? ';' : ',';
    return CsvToListConverter(fieldDelimiter: delimiteur)
        .convert(texte)
        .map((ligne) =>
            ligne.map((cellule) => cellule?.toString() ?? '').toList())
        .toList();
  }

  List<List<String>> _lireExcel(List<int> octets) {
    final excel = Excel.decodeBytes(octets);
    if (excel.tables.isEmpty)
      throw const FormatException('Aucune feuille trouvée.');
    final feuille = excel.tables[excel.tables.keys.first];
    if (feuille == null) throw const FormatException('Feuille illisible.');
    return feuille.rows
        .map((ligne) =>
            ligne.map((cellule) => cellule?.value?.toString() ?? '').toList())
        .toList();
  }

  String _entete(String valeur) => valeur
      .trim()
      .toLowerCase()
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('à', 'a')
      .replaceAll(RegExp(r'\s+'), '_');

  List<_LigneCatalogue> _lireLignes(List<List<String>> tableau) {
    if (tableau.length < 2)
      throw const FormatException(
          'Le fichier ne contient aucune ligne produit.');
    final entetes = tableau.first.map(_entete).toList();
    final index = {for (var i = 0; i < entetes.length; i++) entetes[i]: i};
    for (final obligatoire in const ['reference', 'nom']) {
      if (!index.containsKey(obligatoire)) {
        throw FormatException('Colonne obligatoire absente : $obligatoire');
      }
    }

    String cellule(List<String> ligne, String nom) {
      final i = index[nom];
      return i == null || i >= ligne.length ? '' : ligne[i].trim();
    }

    final lignes = <_LigneCatalogue>[];
    final references = <String>{};
    for (var i = 1; i < tableau.length; i++) {
      final ligne = tableau[i];
      if (ligne.every((valeur) => valeur.trim().isEmpty)) continue;
      final reference = cellule(ligne, 'reference').toUpperCase();
      final nom = cellule(ligne, 'nom');
      if (!RegExp(r'^[A-Z0-9][A-Z0-9._-]{0,39}$').hasMatch(reference)) {
        throw FormatException('Référence invalide à la ligne ${i + 1}.');
      }
      if (nom.length < 2)
        throw FormatException('Nom manquant à la ligne ${i + 1}.');
      if (!references.add(reference)) {
        throw FormatException('Référence dupliquée : $reference.');
      }

      final caracteristiquesTexte = cellule(ligne, 'caracteristiques');
      Map<String, dynamic> caracteristiques = {};
      if (caracteristiquesTexte.isNotEmpty) {
        final decode = jsonDecode(caracteristiquesTexte);
        if (decode is! Map<String, dynamic>) {
          throw FormatException(
              'Caractéristiques invalides à la ligne ${i + 1}.');
        }
        caracteristiques = decode;
      }

      lignes.add(_LigneCatalogue(
        reference: reference,
        nom: nom,
        categorie: cellule(ligne, 'categorie'),
        format: cellule(ligne, 'format'),
        description: cellule(ligne, 'description'),
        caracteristiques: caracteristiques,
      ));
    }
    if (lignes.isEmpty)
      throw const FormatException('Aucune ligne produit valide.');
    if (lignes.length > 500)
      throw const FormatException('Limite de 500 produits par import.');
    return lignes;
  }

  Future<void> _choisirZip() async {
    final resultat = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: true,
    );
    if (resultat == null || !mounted) return;
    final fichier = resultat.files.single;
    final octets = fichier.bytes;
    if (octets == null || octets.isEmpty || octets.length > _limiteZip) {
      setState(() => _erreur = 'Archive vide ou supérieure à 20 Mo.');
      return;
    }

    try {
      final images = <String, List<int>>{};
      var totalImages = 0;
      for (final fichierZip in ZipDecoder().decodeBytes(octets)) {
        if (!fichierZip.isFile) continue;
        final nom = fichierZip.name.split('/').last.split('\\').last;
        final extension = _extension(nom);
        if (!_extensionsImage.contains(extension)) continue;
        final reference = nom.substring(0, nom.lastIndexOf('.')).toUpperCase();
        if (!RegExp(r'^[A-Z0-9][A-Z0-9._-]{0,39}$').hasMatch(reference))
          continue;
        if (images.containsKey(reference)) {
          throw FormatException('Deux images portent la référence $reference.');
        }
        final contenu = Uint8List.fromList(
          List<int>.from(fichierZip.content as List<int>),
        );
        if (contenu.isNotEmpty) {
          if (contenu.length > _limiteImage) {
            throw FormatException('Image supérieure à 5 Mo pour $reference.');
          }
          totalImages += contenu.length;
          if (totalImages > _limitePhotosDecompressees) {
            throw const FormatException(
                'Les images décompressées dépassent 80 Mo.');
          }
          images[reference] = contenu;
        }
      }

      final manquantes = _lignes
          .where((ligne) => !images.containsKey(ligne.reference))
          .map((ligne) => ligne.reference)
          .toList();
      setState(() {
        _nomZip = fichier.name;
        _zip = octets;
        _images = images;
        _erreur = manquantes.isEmpty
            ? null
            : 'Image manquante pour : ${manquantes.take(6).join(', ')}${manquantes.length > 6 ? '…' : ''}';
      });
    } catch (e) {
      setState(() => _erreur = 'Archive illisible : $e');
    }
  }

  Future<void> _choisirPdf() async {
    final resultat = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (resultat == null || !mounted) return;
    final fichier = resultat.files.single;
    final octets = fichier.bytes;
    if (octets == null || octets.isEmpty || octets.length > _limiteTableur) {
      setState(() => _erreur = 'PDF vide ou supérieur à 20 Mo.');
      return;
    }
    if (octets.length < 5 || String.fromCharCodes(octets.take(5)) != '%PDF-') {
      setState(() => _erreur = 'Le fichier joint n’est pas un PDF valide.');
      return;
    }
    setState(() {
      _nomPdf = fichier.name;
      _pdf = octets;
      _erreur = null;
    });
  }

  String _mimeImage(String extension) => switch (extension) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        _ => 'image/webp',
      };

  String _nomSecurise(String valeur) => valeur
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
      .replaceAll(RegExp(r'_+'), '_');

  Future<String> _televerser(
    String chemin,
    List<int> octets,
    String mime,
  ) async {
    await supabase.storage.from('catalogue').uploadBinary(
          chemin,
          Uint8List.fromList(octets),
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
    return supabase.storage.from('catalogue').getPublicUrl(chemin);
  }

  Future<String> _televerserPrive(
    String chemin,
    List<int> octets,
    String mime,
  ) async {
    await supabase.storage.from('catalogue-imports').uploadBinary(
          chemin,
          Uint8List.fromList(octets),
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
    return chemin;
  }

  Future<void> _importer() async {
    if (_occupe ||
        _tableur == null ||
        _zip == null ||
        _erreur != null ||
        _fabricantId == null) return;
    final utilisateurId = supabase.auth.currentUser?.id;
    if (utilisateurId == null) {
      setState(() => _erreur = 'Session expirée. Reconnectez-vous.');
      return;
    }

    setState(() {
      _occupe = true;
      _erreur = null;
    });

    final dossier = 'imports/${DateTime.now().millisecondsSinceEpoch}';
    final televerses = <({String bucket, String path})>[];
    try {
      final fichierTableur = _nomSecurise(_nomTableur ?? 'catalogue.csv');
      final cheminTableur = await _televerserPrive(
        '$utilisateurId/$dossier/$fichierTableur',
        _tableur!,
        _extension(fichierTableur) == 'csv'
            ? 'text/csv'
            : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      televerses.add((bucket: 'catalogue-imports', path: cheminTableur));

      String? cheminPdf;
      if (_pdf != null) {
        final nom = _nomSecurise(_nomPdf ?? 'document.pdf');
        cheminPdf = await _televerserPrive(
          '$utilisateurId/$dossier/$nom',
          _pdf!,
          'application/pdf',
        );
        televerses.add((bucket: 'catalogue-imports', path: cheminPdf));
      }

      final urlsImages = <String, String>{};
      final references = _images.keys.toList();
      for (var debut = 0; debut < references.length; debut += 8) {
        final lot = references.skip(debut).take(8).toList();
        final urls = await Future.wait(lot.map((reference) async {
          final nom = _nomZipImage(reference);
          final extension = _extension(nom);
          final chemin = '$utilisateurId/$dossier/images/$nom';
          final url = await _televerser(
              chemin, _images[reference]!, _mimeImage(extension));
          televerses.add((bucket: 'catalogue', path: chemin));
          return MapEntry(reference, url);
        }));
        urlsImages.addEntries(urls);
      }

      await supabase.rpc('importer_catalogue', params: {
        'p_fabricant_id': _fabricantId,
        'p_fichier_tableur': cheminTableur,
        'p_document_pdf_url': cheminPdf,
        'p_lignes': _lignes
            .map((ligne) => ligne.versJson(urlsImages[ligne.reference]!))
            .toList(),
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      for (final fichier in televerses) {
        try {
          await supabase.storage.from(fichier.bucket).remove([fichier.path]);
        } catch (_) {}
      }
      if (mounted) setState(() => _erreur = 'Import refusé : ${e.toString()}');
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _soumettrePdf() async {
    if (_occupe || _pdf == null || _fabricantId == null) return;
    final utilisateurId = supabase.auth.currentUser?.id;
    if (utilisateurId == null) {
      setState(() => _erreur = 'Session expirée. Reconnectez-vous.');
      return;
    }

    setState(() {
      _occupe = true;
      _erreur = null;
    });

    String? cheminPdf;
    try {
      final nom = _nomSecurise(_nomPdf ?? 'catalogue.pdf');
      cheminPdf = '$utilisateurId/catalogues-pdf/'
          '${DateTime.now().millisecondsSinceEpoch}_$nom';
      await _televerserPrive(cheminPdf, _pdf!, 'application/pdf');
      await supabase.rpc('soumettre_catalogue_pdf', params: {
        'p_fabricant_id': _fabricantId,
        'p_fichier_pdf': cheminPdf,
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (cheminPdf != null) {
        try {
          await supabase.storage.from('catalogue-imports').remove([cheminPdf]);
        } catch (_) {}
      }
      if (mounted) setState(() => _erreur = 'Envoi refusé : ${e.toString()}');
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  String _nomZipImage(String reference) {
    for (final fichier in ZipDecoder().decodeBytes(_zip!)) {
      if (!fichier.isFile) continue;
      final nom = fichier.name.split('/').last.split('\\').last;
      if (!_extensionsImage.contains(_extension(nom))) continue;
      if (nom.substring(0, nom.lastIndexOf('.')).toUpperCase() == reference)
        return nom;
    }
    throw FormatException('Image absente pour $reference.');
  }

  @override
  Widget build(BuildContext context) {
    final largeur = MediaQuery.sizeOf(context).width;
    final contenu = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.fabricantInitial == null)
            DropdownButtonFormField<String>(
              initialValue: _fabricantId,
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'Marque du catalogue'),
              items: widget.marques
                  .map((marque) => DropdownMenuItem(
                        value: marque['fabricant_id'] as String,
                        child: Text(
                          marque['fabricant_nom'] as String? ?? '',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: _occupe
                  ? null
                  : (valeur) => setState(() => _fabricantId = valeur),
            ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.table_view_outlined),
                label: Text('Excel / CSV'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.picture_as_pdf_outlined),
                label: Text('PDF à traiter'),
              ),
            ],
            selected: {_pdfSeul},
            onSelectionChanged: _occupe
                ? null
                : (selection) => setState(() {
                      _pdfSeul = selection.first;
                      _erreur = null;
                    }),
          ),
          const SizedBox(height: 12),
          if (_pdfSeul) ...[
            OutlinedButton.icon(
              onPressed: _occupe ? null : _choisirPdf,
              icon: const Icon(Icons.attach_file),
              label: Text(_nomPdf ?? 'Joindre le PDF du catalogue'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Le PDF sera conservé dans un espace privé et transmis à l’équipe pour traitement manuel. Aucun produit ne sera créé avant validation.',
              style: TextStyle(fontSize: 12, height: 1.45),
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed: _occupe ? null : _choisirTableur,
              icon: const Icon(Icons.attach_file),
              label: Text(_nomTableur ?? 'Joindre XLSX ou CSV'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _occupe || _lignes.isEmpty ? null : _choisirZip,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(_nomZip ?? 'Joindre le ZIP des images'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _occupe ? null : _choisirPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(_nomPdf ?? 'Joindre le PDF source (facultatif)'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Colonnes requises : reference, nom. Colonnes facultatives : categorie, format, description, caracteristiques (JSON). Images : REF.jpg, REF.png ou REF.webp dans le ZIP.',
              style: TextStyle(fontSize: 12, height: 1.45),
            ),
          ],
          if (_lignes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
                '${_lignes.length} références détectées · ${_images.length} images associées'),
            const SizedBox(height: 8),
            ..._lignes.take(8).map((ligne) {
              final image = _images[ligne.reference];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  image == null
                      ? Icons.image_not_supported_outlined
                      : Icons.check_circle_outline,
                  color: image == null
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
                title: Text(ligne.nom,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${ligne.reference} · ${ligne.categorie} · ${ligne.format}'),
              );
            }),
            if (_lignes.length > 8)
              Text('… et ${_lignes.length - 8} autres références'),
          ],
          if (_erreur != null) ...[
            const SizedBox(height: 12),
            Text(_erreur!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );

    return AlertDialog(
      title: const Text('Importer un catalogue'),
      content: SizedBox(
        width: largeur < 600 ? double.maxFinite : 520,
        child: contenu,
      ),
      actions: [
        TextButton(
          onPressed: _occupe ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _occupe ||
                  _fabricantId == null ||
                  (_pdfSeul
                      ? _pdf == null
                      : _lignes.isEmpty || _images.length < _lignes.length)
              ? null
              : _pdfSeul
                  ? _soumettrePdf
                  : _importer,
          icon: _occupe
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_file),
          label: Text(_occupe
              ? (_pdfSeul ? 'Envoi…' : 'Import…')
              : _pdfSeul
                  ? 'Envoyer le PDF'
                  : 'Importer ${_lignes.length} produits'),
        ),
      ],
    );
  }
}
