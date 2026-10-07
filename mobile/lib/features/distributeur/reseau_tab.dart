import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/import_catalogue_dialog.dart';
import '../../core/supabase.dart';
import '../../core/widgets.dart';

/// Les marques et les boutiques du distributeur.
///
/// CE QUE CET ÉCRAN DÉBLOQUE, et c'est plus important qu'il n'y paraît. Le
/// destinataire d'une rupture est décidé par un trigger, qui lit
/// `attributions_reseau.distributeur_id`. Tant que personne ne pouvait
/// renseigner cette colonne depuis l'application, toute rupture naissait sans
/// destinataire : elle n'apparaissait dans aucun carnet, et n'existait qu'après
/// escalade, deux heures plus tard, pour tout le monde à la fois. Le cercle
/// « attribué », qui est le cœur du modèle, était inatteignable.
///
/// Une marque n'existe ici que par les boutiques qu'elle couvre. Déclarer
/// « je porte Coca-Cola » sans boutique ne change rien au routage, et l'écran ne
/// le propose donc pas : il fait choisir une boutique, puis la marque.
class ReseauTab extends StatefulWidget {
  const ReseauTab({super.key, required this.cle});

  final int cle;

  @override
  State<ReseauTab> createState() => _ReseauTabState();
}

class _ReseauTabState extends State<ReseauTab> {
  late Future<_Reseau> _reseau;

  @override
  void initState() {
    super.initState();
    _reseau = _charger();
  }

  @override
  void didUpdateWidget(ReseauTab ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.cle != widget.cle) _rafraichir();
  }

  Future<_Reseau> _charger() async {
    // Les deux vues sont sous RLS : elles ne rendent que le réseau de ce
    // distributeur, sans qu'aucun identifiant soit envoyé depuis le téléphone.
    final marques =
        await supabase.from('v_mes_marques').select().order('fabricant_nom');
    final boutiques = await supabase
        .from('v_mon_reseau')
        .select()
        .order('commune')
        .order('point_de_vente_nom');

    return _Reseau(
      marques: List<Map<String, dynamic>>.from(marques),
      boutiques: List<Map<String, dynamic>>.from(boutiques),
    );
  }

  Future<void> _rafraichir() async {
    final f = _charger();
    if (mounted) setState(() => _reseau = f);
    await f;
  }

  Future<void> _revendiquer() async {
    final choix = await showModalBottomSheet<_Revendication>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ChoixBoutique(),
    );
    if (choix == null) return;

    try {
      await supabase.rpc('revendiquer_point_de_vente', params: {
        'p_point_de_vente_id': choix.pointDeVenteId,
        'p_fabricant_id': choix.fabricantId,
      });
      _message(
          'Boutique ajoutée à votre réseau. Ses ruptures vous parviendront '
          'désormais dès la première seconde.');
      await _rafraichir();
    } catch (e) {
      if (!mounted) return;
      _message(messageErreur(context, e));
    }
  }

  Future<void> _renoncer(Map<String, dynamic> ligne) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Retirer ${ligne['point_de_vente_nom']} ?'),
        content: Text(
          'Vous ne recevrez plus ses ruptures sur ${ligne['fabricant_nom']} '
          'dès le signalement. Elles ne vous parviendront qu\'après escalade, '
          'et en concurrence avec les autres distributeurs de la commune.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    try {
      await supabase.rpc('renoncer_point_de_vente', params: {
        'p_point_de_vente_id': ligne['point_de_vente_id'],
        'p_fabricant_id': ligne['fabricant_id'],
      });
      await _rafraichir();
    } catch (e) {
      if (!mounted) return;
      _message(messageErreur(context, e));
    }
  }

  Future<void> _ajouterProduit() async {
    final marques = List<Map<String, dynamic>>.from(
      await supabase
          .from('v_mes_marques')
          .select('fabricant_id, fabricant_nom')
          .order('fabricant_nom'),
    );
    if (!mounted || marques.isEmpty) {
      _message('Aucun catalogue autorisé par un fabricant.');
      return;
    }
    final importe = await ouvrirImportCatalogue(context, marques: marques);
    if (importe == true && mounted) await _rafraichir();
  }

  void _message(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texte)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _revendiquer,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Ajouter une boutique'),
      ),
      body: RefreshIndicator(
        onRefresh: _rafraichir,
        child: FutureBuilder<_Reseau>(
          future: _reseau,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return EtatVide(
                icone: Icons.cloud_off_outlined,
                titre: 'Chargement impossible',
                message: messageErreur(context, snap.error!),
              );
            }

            final reseau = snap.data!;
            if (reseau.boutiques.isEmpty) {
              return EtatVide(
                icone: Icons.storefront_outlined,
                titre: 'Aucune boutique déclarée',
                message: 'Tant que vous n\'avez déclaré aucune boutique, les '
                    'ruptures ne vous sont adressées qu\'après deux heures '
                    'd\'escalade, et en concurrence avec les autres. Déclarez '
                    'celles que vous desservez déjà.',
                action: 'Ajouter une boutique',
                onAction: _revendiquer,
              );
            }

            // Regroupement par commune : c'est ainsi qu'un distributeur pense
            // son secteur, pas par ordre alphabétique de boutique.
            final communes = <String, List<Map<String, dynamic>>>{};
            for (final b in reseau.boutiques) {
              communes
                  .putIfAbsent(b['commune'] as String? ?? '—', () => [])
                  .add(b);
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              children: [
                TitreSection('Mes marques', detail: '${reseau.marques.length}'),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    onPressed: _ajouterProduit,
                    icon: const Icon(Icons.add_box_outlined),
                    label: const Text('Importer par fichier'),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: reseau.marques
                      .map((m) => Chip(
                            avatar: const Icon(Icons.local_offer_outlined,
                                size: 16),
                            label: Text(
                              '${m['fabricant_nom']} · ${m['boutiques']} boutique(s)',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                for (final entree in communes.entries) ...[
                  TitreSection(entree.key,
                      detail: '${entree.value.length} boutique(s)'),
                  ...entree.value.map(
                    (b) => _Boutique(ligne: b, onRetirer: () => _renoncer(b)),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Reseau {
  const _Reseau({required this.marques, required this.boutiques});
  final List<Map<String, dynamic>> marques;
  final List<Map<String, dynamic>> boutiques;
}

class _Boutique extends StatelessWidget {
  const _Boutique({required this.ligne, required this.onRetirer});

  final Map<String, dynamic> ligne;
  final VoidCallback onRetirer;

  @override
  Widget build(BuildContext context) {
    final ouvertes = (ligne['ruptures_ouvertes'] as num?)?.toInt() ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        leading: Icon(
          Icons.storefront_outlined,
          color: ouvertes > 0 ? Colors.orange : null,
        ),
        title: Text(ligne['point_de_vente_nom'] as String? ?? ''),
        subtitle: Text(
          '${ligne['fabricant_nom']}'
          '${ouvertes > 0 ? ' · $ouvertes rupture(s) ouverte(s)' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: IconButton(
          tooltip: 'Retirer de mon réseau',
          icon: const Icon(Icons.link_off),
          onPressed: onRetirer,
        ),
      ),
    );
  }
}

class _Revendication {
  const _Revendication(
      {required this.pointDeVenteId, required this.fabricantId});
  final String pointDeVenteId;
  final String fabricantId;
}

/// Choisir une boutique, puis la marque.
///
/// Les boutiques proposées sont celles que RLS laisse voir : celles déjà
/// desservies, et celles des communes où ce distributeur opère déjà. Un
/// distributeur qui démarre ne voit donc rien, et c'est la limite assumée du
/// pilote : sa première boutique lui est attribuée par l'administrateur, ce qui
/// ouvre ensuite sa commune.
class _ChoixBoutique extends StatefulWidget {
  const _ChoixBoutique();

  @override
  State<_ChoixBoutique> createState() => _ChoixBoutiqueState();
}

class _ChoixBoutiqueState extends State<_ChoixBoutique> {
  late Future<List<Map<String, dynamic>>> _boutiques;
  String _filtre = '';

  @override
  void initState() {
    super.initState();
    _boutiques = _charger();
  }

  Future<List<Map<String, dynamic>>> _charger() async {
    final lignes = await supabase
        .from('points_de_vente')
        .select('id, nom, commune, type_activite, telephone')
        .eq('statut', 'actif')
        .order('commune')
        .order('nom');
    return List<Map<String, dynamic>>.from(lignes);
  }

  Future<void> _choisirMarque(Map<String, dynamic> boutique) async {
    final fabricants = List<Map<String, dynamic>>.from(
      await supabase.from('fabricants').select('id, nom').order('nom'),
    );
    if (!mounted) return;

    final fabricantId = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Quelle marque pour ${boutique['nom']} ?'),
        children: fabricants
            .map((f) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, f['id'] as String),
                  child: Text(f['nom'] as String? ?? ''),
                ))
            .toList(),
      ),
    );
    if (fabricantId == null || !mounted) return;

    Navigator.pop(
      context,
      _Revendication(
        pointDeVenteId: boutique['id'] as String,
        fabricantId: fabricantId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (context, controleur) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Choisir une boutique',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Nom ou commune',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filtre = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _boutiques,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final toutes = snap.data ?? const <Map<String, dynamic>>[];
                final liste = toutes.where((b) {
                  if (_filtre.isEmpty) return true;
                  final texte = '${b['nom']} ${b['commune']}'.toLowerCase();
                  return texte.contains(_filtre);
                }).toList();

                if (liste.isEmpty) {
                  return const EtatVide(
                    icone: Icons.search_off,
                    titre: 'Aucune boutique',
                    message: 'Vous ne voyez que les boutiques des communes où '
                        'vous opérez déjà. Pour ouvrir une nouvelle commune, '
                        'votre première boutique doit vous être attribuée par '
                        'l\'administrateur du réseau.',
                  );
                }

                return ListView.builder(
                  controller: controleur,
                  itemCount: liste.length,
                  itemBuilder: (context, i) {
                    final b = liste[i];
                    return ListTile(
                      leading: const Icon(Icons.storefront_outlined),
                      title: Text(b['nom'] as String? ?? ''),
                      subtitle: Text('${b['commune']} · ${b['type_activite']}'),
                      onTap: () => _choisirMarque(b),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
