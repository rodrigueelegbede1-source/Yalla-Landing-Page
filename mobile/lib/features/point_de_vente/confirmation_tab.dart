import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/vignette_produit.dart';
import '../../core/widgets.dart';
import '../../l10n/app_localizations.dart';

/// Les ruptures que la caisse a détectées et que le boutiquier doit confirmer.
///
/// CE QUE CET ÉCRAN COÛTE AU PRODUIT, et pourquoi il existe quand même. Le
/// mécanisme d'origine était qu'une vente vidant un stock partait toute seule,
/// sans que le boutiquier ait rien à faire : c'était l'argument central, celui
/// qui rendait le signalement automatique possible chez quelqu'un qui n'a
/// aucune raison spontanée de déclarer ses ruptures.
///
/// Demander une confirmation réintroduit un geste. En échange, elle évite
/// d'envoyer un livreur pour un stock mal saisi, et laisse corriger la quantité
/// avant qu'elle ne parte. C'est un arbitrage tranché en connaissance de cause.
///
/// TOUT LE SOIN DE CET ÉCRAN VA DONC À RENDRE CE GESTE QUASI GRATUIT :
///
///   * il s'ouvre de lui-même juste après l'encaissement, au moment où le
///     boutiquier tient encore son téléphone ;
///   * chaque demande tient sur une ligne, avec deux boutons et rien d'autre ;
///   * la quantité est pré-remplie avec ce que la caisse a vu sortir, et se
///     corrige d'un geste sans ouvrir de clavier.
///
/// Une demande sans réponse est purgée au bout de vingt-quatre heures, et ne
/// compte pas comme une rupture non servie : personne n'a jamais été sollicité.
class ConfirmationTab extends StatefulWidget {
  const ConfirmationTab({super.key, required this.cle, required this.onChangement});

  final int cle;
  final VoidCallback onChangement;

  @override
  State<ConfirmationTab> createState() => _ConfirmationTabState();
}

class _ConfirmationTabState extends State<ConfirmationTab> {
  late Future<List<Map<String, dynamic>>> _demandes;

  @override
  void initState() {
    super.initState();
    _demandes = _charger();
  }

  @override
  void didUpdateWidget(ConfirmationTab ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.cle != widget.cle) _rafraichir();
  }

  Future<List<Map<String, dynamic>>> _charger() async {
    final lignes = await supabase
        .from('v_ruptures_a_confirmer')
        .select()
        .order('date_signalement', ascending: false);
    return List<Map<String, dynamic>>.from(lignes);
  }

  Future<void> _rafraichir() async {
    final f = _charger();
    if (mounted) setState(() => _demandes = f);
    await f;
  }

  Future<void> _confirmer(Map<String, dynamic> demande) async {
    final l = L.of(context);
    final proposee = (demande['quantite_demandee'] as num?)?.toInt() ?? 1;

    final quantite = await showModalBottomSheet<int>(
      context: context,
      builder: (_) => _ChoixQuantite(
        nom: demande['produit_nom'] as String? ?? '',
        imageUrl: demande['image_url'] as String?,
        categorie: demande['categorie_nom'] as String?,
        proposee: proposee,
      ),
    );
    if (quantite == null || !mounted) return;

    try {
      await supabase.rpc('confirmer_rupture', params: {
        'p_rupture_id': demande['rupture_id'],
        'p_quantite': quantite,
      });
      _message(l.ruptureConfirmee);
      widget.onChangement();
      await _rafraichir();
    } catch (e) {
      if (!mounted) return;
      _message(messageErreur(context, e));
    }
  }

  Future<void> _rejeter(Map<String, dynamic> demande) async {
    final l = L.of(context);
    try {
      await supabase.rpc('rejeter_rupture',
          params: {'p_rupture_id': demande['rupture_id']});
      _message(l.ruptureRejetee);
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

          final demandes = snap.data ?? const [];
          if (demandes.isEmpty) {
            return EtatVide(
              icone: Icons.check_circle_outline,
              titre: l.carnetVideTitre,
              message: l.aConfirmerExplication,
            );
          }

          return ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 24),
            children: [
              TitreSection(l.aConfirmerTitre,
                  detail: l.aConfirmerCompteur(demandes.length)),
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 12),
                child: Text(l.aConfirmerExplication,
                    style: const TextStyle(fontSize: 12, height: 1.4)),
              ),
              ...demandes.map((d) => _Demande(
                    demande: d,
                    onConfirmer: () => _confirmer(d),
                    onRejeter: () => _rejeter(d),
                  )),
            ],
          );
        },
      ),
    );
  }
}

class _Demande extends StatelessWidget {
  const _Demande({
    required this.demande,
    required this.onConfirmer,
    required this.onRejeter,
  });

  final Map<String, dynamic> demande;
  final VoidCallback onConfirmer;
  final VoidCallback onRejeter;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final anciennete = (demande['anciennete_secondes'] as num?)?.toInt() ?? 0;

    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                VignetteProduit(
                  nom: demande['produit_nom'] as String? ?? '',
                  imageUrl: demande['image_url'] as String?,
                  categorie: demande['categorie_nom'] as String?,
                  taille: 48,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(demande['produit_nom'] as String? ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        '${demande['fabricant_nom'] ?? ''} · '
                        '${l.detecteeIlYA(duree(anciennete))}',
                        style: const TextStyle(fontSize: 11.5, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onRejeter,
                    child: Text(l.rejeterLaRupture,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: onConfirmer,
                    child: Text(l.confirmerLaRupture),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Le choix de la quantité, sans clavier.
///
/// Un boutiquier debout derrière son comptoir ne tape pas un nombre : il
/// appuie. Les paliers couvrent ce qu'on commande réellement, et la valeur
/// proposée est celle que la caisse a vu sortir.
class _ChoixQuantite extends StatefulWidget {
  const _ChoixQuantite({
    required this.nom,
    required this.proposee,
    this.imageUrl,
    this.categorie,
  });

  final String nom;
  final int proposee;
  final String? imageUrl;
  final String? categorie;

  @override
  State<_ChoixQuantite> createState() => _ChoixQuantiteState();
}

class _ChoixQuantiteState extends State<_ChoixQuantite> {
  late int _quantite = widget.proposee < 1 ? 1 : widget.proposee;

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
            Text(l.combienDeCartons,
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  onPressed: _quantite > 1
                      ? () => setState(() => _quantite--)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    '$_quantite',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 34, fontWeight: FontWeight.w700),
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
              child: Text(l.confirmerLaRupture),
            ),
          ],
        ),
      ),
    );
  }
}
