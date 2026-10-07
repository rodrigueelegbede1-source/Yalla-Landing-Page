import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/communications_tabs.dart';
import '../../core/supabase.dart';
import 'catalogue_admin_tab.dart';
import 'supervision_tabs.dart';

class AdministrateurHomeScreen extends ConsumerStatefulWidget {
  const AdministrateurHomeScreen({super.key});
  @override
  ConsumerState<AdministrateurHomeScreen> createState() =>
      _AdministrateurHomeScreenState();
}

class _AdministrateurHomeScreenState
    extends ConsumerState<AdministrateurHomeScreen> {
  int _onglet = 0;
  late Future<List<Map<String, dynamic>>> _acteurs;
  late Future<Map<String, dynamic>> _supervision;
  late Future<List<Map<String, dynamic>>> _communes;
  late Future<List<Map<String, dynamic>>> _anomalies;

  @override
  void initState() {
    super.initState();
    _acteurs = _charger();
    _supervision = _chargerSupervision();
    _communes = _chargerCommunes();
    _anomalies = _chargerAnomalies();
  }

  Future<List<Map<String, dynamic>>> _charger() async {
    final rows = await supabase
        .from('v_acteurs_admin')
        .select()
        .order('role')
        .order('nom');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> _chargerSupervision() async {
    final row = await supabase.from('v_supervision_reseau').select().single();
    return Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> _chargerCommunes() async {
    final rows = await supabase
        .from('v_supervision_communes')
        .select()
        .order('points', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> _chargerAnomalies() async {
    final rows = await supabase
        .from('v_anomalies_reseau')
        .select()
        .order('depuis', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _rafraichir() async {
    setState(() {
      _acteurs = _charger();
      _supervision = _chargerSupervision();
      _communes = _chargerCommunes();
      _anomalies = _chargerAnomalies();
    });
    await Future.wait<Object?>([_acteurs, _supervision, _communes, _anomalies]);
  }

  Future<void> _ajouter() async {
    final result = await showDialog<_NouveauCompte>(
        context: context, builder: (_) => const _NouveauCompteDialog());
    if (result == null || !mounted) return;
    try {
      final response = await supabase.functions.invoke('creer-compte', body: {
        'nom': result.nom,
        'telephone': result.telephone,
        'role': result.role,
        'mot_de_passe': result.motDePasse,
        'details': result.details,
      });
      final data = response.data as Map?;
      if (data?['erreur'] != null) throw Exception(data?['erreur']);
      await _rafraichir();
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
                  title: const Text('Compte créé'),
                  content: Text(
                      'Identifiant : ${result.telephone}\nMot de passe : ${result.motDePasse}\n\nRemettez ces accès en main propre.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Fermer'))
                  ]));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Création impossible : $e')));
    }
  }

  Future<void> _retirer(Map<String, dynamic> acteur) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                title: Text('Retirer ${acteur['libelle']} ?'),
                content: const Text(
                    'L’acteur sera désactivé sans supprimer son historique.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Annuler')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Retirer'))
                ]));
    if (ok != true || !mounted) return;
    try {
      await supabase.rpc('retirer_acteur',
          params: {'p_role': acteur['role'], 'p_id': acteur['id_metier']});
      await _rafraichir();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Retrait impossible : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    const titres = [
      'Vue réseau',
      'Communes',
      'Acteurs',
      'Alertes',
      'Catalogue',
      'Communications',
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(titres[_onglet]),
        actions: [
          if (_onglet == 2)
            IconButton(
                onPressed: _ajouter,
                icon: const Icon(Icons.person_add),
                tooltip: 'Ajouter un acteur'),
          IconButton(
            onPressed: () => setState(() => _onglet = 4),
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: 'Catalogue produit',
          ),
          IconButton(
            onPressed: () => setState(() => _onglet = 5),
            icon: const Icon(Icons.campaign_outlined),
            tooltip: 'Communications à valider',
          ),
          IconButton(
              onPressed: _rafraichir,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualiser'),
          IconButton(
              onPressed: () => ref.read(authProvider).deconnecter(),
              icon: const Icon(Icons.logout),
              tooltip: 'Se déconnecter'),
        ],
      ),
      body: IndexedStack(
        index: _onglet,
        children: [
          AdministrateurApercuTab(
              supervision: _supervision,
              communes: _communes,
              onRefresh: _rafraichir),
          AdministrateurCommunesTab(future: _communes),
          _listeActeurs(),
          AdministrateurAlertesTab(future: _anomalies),
          const CatalogueAdminTab(),
          CommunicationsAdministrateurTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _onglet < 4 ? _onglet : 0,
        onDestinationSelected: (index) => setState(() => _onglet = index),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined), label: 'Vue réseau'),
          NavigationDestination(
              icon: Icon(Icons.map_outlined), label: 'Communes'),
          NavigationDestination(
              icon: Icon(Icons.groups_outlined), label: 'Acteurs'),
          NavigationDestination(
              icon: Icon(Icons.warning_amber_outlined), label: 'Alertes'),
        ],
      ),
    );
  }

  Widget _listeActeurs() => FutureBuilder<List<Map<String, dynamic>>>(
        future: _acteurs,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Acteurs indisponibles : ${snap.error}'));
          }
          final rows = snap.data ?? const [];
          return RefreshIndicator(
            onRefresh: _rafraichir,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Acteurs du réseau',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text(
                    'Ajoutez ou retirez un fabricant, distributeur, recenseur ou revendeur sans effacer son historique.'),
                const SizedBox(height: 16),
                ...rows
                    .where((a) => a['role'] != 'administrateur')
                    .map((a) => Card(
                          child: ListTile(
                            title: Text(a['libelle'] as String? ??
                                a['nom'] as String? ??
                                ''),
                            subtitle: Text('${a['role']} · ${a['telephone']}'),
                            trailing: IconButton(
                              onPressed: () => _retirer(a),
                              icon: const Icon(Icons.person_remove_outlined),
                              tooltip: 'Retirer',
                            ),
                          ),
                        )),
              ],
            ),
          );
        },
      );
}

class _NouveauCompte {
  const _NouveauCompte(
      {required this.role,
      required this.nom,
      required this.telephone,
      required this.motDePasse,
      required this.details});
  final String role, nom, telephone, motDePasse;
  final Map<String, dynamic> details;
}

class _NouveauCompteDialog extends StatefulWidget {
  const _NouveauCompteDialog();
  @override
  State<_NouveauCompteDialog> createState() => _NouveauCompteDialogState();
}

class _NouveauCompteDialogState extends State<_NouveauCompteDialog> {
  final nom = TextEditingController();
  final telephone = TextEditingController();
  final motDePasse = TextEditingController(text: 'Yalla2026!');
  final societe = TextEditingController();
  String role = 'fabricant';
  @override
  void dispose() {
    nom.dispose();
    telephone.dispose();
    motDePasse.dispose();
    societe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Ajouter un acteur'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
                value: role,
                items: const [
                  DropdownMenuItem(
                      value: 'fabricant', child: Text('Fabricant')),
                  DropdownMenuItem(
                      value: 'distributeur', child: Text('Distributeur')),
                  DropdownMenuItem(
                      value: 'agent_recenseur', child: Text('Agent recenseur')),
                  DropdownMenuItem(
                      value: 'point_de_vente', child: Text('Revendeur'))
                ],
                onChanged: (v) => setState(() => role = v!),
                decoration: const InputDecoration(labelText: 'Rôle')),
            TextField(
                controller: nom,
                decoration: const InputDecoration(labelText: 'Nom')),
            TextField(
                controller: societe,
                decoration:
                    const InputDecoration(labelText: 'Société / revendeur')),
            TextField(
                controller: telephone,
                decoration: const InputDecoration(labelText: 'Téléphone')),
            TextField(
                controller: motDePasse,
                decoration:
                    const InputDecoration(labelText: 'Mot de passe initial'))
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () {
                  if (nom.text.trim().isEmpty ||
                      telephone.text.trim().isEmpty ||
                      motDePasse.text.length < 8) return;
                  Navigator.pop(
                      context,
                      _NouveauCompte(
                          role: role,
                          nom: nom.text.trim(),
                          telephone: telephone.text.trim(),
                          motDePasse: motDePasse.text,
                          details: {
                            'nom_societe': societe.text.trim(),
                            'secteur': 'Abidjan',
                            'nom_boutique': societe.text.trim(),
                            'type_activite': 'boutique',
                            'commune': 'Abidjan',
                            'longitude': '-3.99',
                            'latitude': '5.34'
                          }));
                },
                child: const Text('Créer'))
          ]);
}
