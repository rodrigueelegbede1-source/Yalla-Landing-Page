import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../l10n/app_localizations.dart';
import '../../core/supabase.dart';

/// Les courses en cours du livreur, et leur clôture.
///
/// Le cycle complet : prendre, se rendre sur place, encaisser, livrer. La prise
/// crée la livraison dans la même transaction, il n'y a donc jamais de course
/// prise sans livraison ouverte.
///
/// Deux boutons comptent plus que les autres. **Appeler** : à Abidjan, un
/// livreur qui ne trouve pas une boutique téléphone, il ne cherche pas une
/// adresse. **Abandonner** : une panne de moto ou une boutique fermée doit
/// remettre la rupture en circulation, sinon elle sort du circuit pour de bon.
class LivraisonTab extends StatefulWidget {
  const LivraisonTab({super.key, required this.cle, required this.onChangement});

  /// Change quand une course vient d'être prise dans l'autre onglet.
  final int cle;

  /// Appelé après une livraison ou un abandon, pour rafraîchir la liste des
  /// courses disponibles : une course abandonnée y réapparaît.
  final VoidCallback onChangement;

  @override
  State<LivraisonTab> createState() => _LivraisonTabState();
}

class _LivraisonTabState extends State<LivraisonTab> {
  late Future<List<Map<String, dynamic>>> _courses;

  @override
  void initState() {
    super.initState();
    _courses = _charger();
  }

  @override
  void didUpdateWidget(LivraisonTab ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.cle != widget.cle) _rafraichir();
  }

  Future<List<Map<String, dynamic>>> _charger() async {
    final lignes = await supabase
        .from('v_mes_courses')
        .select()
        .eq('statut_livraison', 'en_cours')
        .order('date_debut');
    return List<Map<String, dynamic>>.from(lignes);
  }

  Future<void> _rafraichir() async {
    final f = _charger();
    if (mounted) setState(() => _courses = f);
    await f;
  }

  Future<void> _appeler(String? telephone) async {
    if (telephone == null || telephone.isEmpty) {
      _message('Aucun numéro renseigné pour cette boutique');
      return;
    }
    final uri = Uri.parse('tel:${telephone.replaceAll(RegExp(r'[^0-9+]'), '')}');
    if (!await launchUrl(uri)) _message('Impossible de lancer l\'appel');
  }

  Future<void> _itineraire(num? latitude, num? longitude, String nom) async {
    if (latitude == null || longitude == null) {
      _message('Position de la boutique inconnue');
      return;
    }
    // Schéma geo: pris en charge par toutes les applications de carte Android,
    // ce qui laisse le livreur utiliser celle qu'il a déjà.
    final uri = Uri.parse('geo:$latitude,$longitude?q=$latitude,$longitude(${Uri.encodeComponent(nom)})');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _message('Aucune application de carte installée');
    }
  }

  Future<void> _livrer(Map<String, dynamic> course) async {
    final encaisse = await _demanderMontant(course['produit_nom'] as String? ?? 'Livraison');
    if (encaisse == null) return;

    try {
      await supabase.rpc('terminer_livraison', params: {
        'p_livraison_id': course['livraison_id'],
        'p_montant': encaisse,
      });
      if (!mounted) return;
      _message('${L.of(context).livraisonTerminee} · ${montant(context, encaisse)}');
    } catch (e) {
      if (!mounted) return;
      _message(messageErreur(context, e));
    }
    await _rafraichir();
    widget.onChangement();
  }

  Future<void> _abandonner(Map<String, dynamic> course) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abandonner cette course ?'),
        content: const Text(
          'La rupture repartira vers votre distributeur et un autre livreur '
          'pourra la prendre. Le délai avant escalade recommencera à zéro.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Non')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Abandonner'),
          ),
        ],
      ),
    );

    if (confirme != true) return;

    try {
      await supabase.rpc('annuler_livraison',
          params: {'p_livraison_id': course['livraison_id']});
      _message('Course remise en circulation');
    } catch (e) {
      if (!mounted) return;
      _message(messageErreur(context, e));
    }
    await _rafraichir();
    widget.onChangement();
  }

  Future<num?> _demanderMontant(String titre) {
    final controleur = TextEditingController();
    return showDialog<num>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titre),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Montant encaissé en espèces'),
            const SizedBox(height: 4),
            const Text(
              'Laissez à zéro si la boutique règle plus tard.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controleur,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                suffixText: 'F',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(context, num.tryParse(controleur.text) ?? 0),
            child: const Text('Confirmer la livraison'),
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
    return RefreshIndicator(
      onRefresh: _rafraichir,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _courses,
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

          final courses = snap.data ?? const [];
          if (courses.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 100),
              Icon(Icons.local_shipping_outlined, size: 56),
              SizedBox(height: 20),
              Text('Aucune course en cours',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Prenez une course dans l\'onglet À proximité pour la voir '
                  'apparaître ici.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ]);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: courses.length,
            itemBuilder: (context, i) {
              final c = courses[i];
              final quantite = c['quantite_demandee'] as int?;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c['produit_nom'] as String? ?? 'Produit',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      if (quantite != null || c['fabricant_nom'] != null)
                        Text(
                          [
                            if (quantite != null) '$quantite carton(s)',
                            if (c['fabricant_nom'] != null) c['fabricant_nom'] as String,
                          ].join(' · '),
                          style: const TextStyle(fontSize: 13),
                        ),
                      const Divider(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.storefront_outlined, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c['point_de_vente_nom'] as String? ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(
                                  [
                                    c['adresse'],
                                    c['commune'],
                                  ].whereType<String>().join(' · '),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                if (c['gerant_nom'] != null)
                                  Text('Gérant : ${c['gerant_nom']}',
                                      style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.phone, size: 18),
                              label: const Text('Appeler'),
                              onPressed: () =>
                                  _appeler(c['point_de_vente_telephone'] as String?),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.navigation_outlined, size: 18),
                              label: const Text('Y aller'),
                              onPressed: () => _itineraire(
                                c['latitude'] as num?,
                                c['longitude'] as num?,
                                c['point_de_vente_nom'] as String? ?? 'Boutique',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('Livrer'),
                              onPressed: () => _livrer(c),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => _abandonner(c),
                            child: const Text('Abandonner'),
                          ),
                        ],
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
