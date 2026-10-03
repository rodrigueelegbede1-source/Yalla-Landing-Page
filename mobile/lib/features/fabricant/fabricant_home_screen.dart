import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/retours_recus_tab.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../core/vignette_produit.dart';
import '../../core/widgets.dart';
import 'apercu_tab.dart';

class FabricantHomeScreen extends ConsumerStatefulWidget {
  const FabricantHomeScreen({super.key, required this.fabricantId});

  final String fabricantId;

  @override
  ConsumerState<FabricantHomeScreen> createState() => _FabricantHomeScreenState();
}

class _FabricantHomeScreenState extends ConsumerState<FabricantHomeScreen> {
  int _onglet = 0;
  int _cle = 0;

  Future<List<Map<String, dynamic>>> _catalogue() async {
    final rows = await supabase.from('v_mon_catalogue').select().order('nom');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> _ruptures() async {
    final rows = await supabase.from('v_mes_ruptures').select().order('date_signalement', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>?> _tauxService() async {
    final row = await supabase.from('v_taux_de_service_par_fabricant').select().maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>> _apercu() async {
    final donnees = await Future.wait<Object?>([_catalogue(), _ruptures(), _tauxService()]);
    return {
      'catalogue': donnees[0] as List<Map<String, dynamic>>,
      'ruptures': donnees[1] as List<Map<String, dynamic>>,
      'service': donnees[2] as Map<String, dynamic>?,
    };
  }

  Future<void> _ajouterProduit() async {
    final nom = TextEditingController();
    final categorie = TextEditingController(text: 'Boissons');
    final reference = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ajouter au catalogue'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nom, autofocus: true, decoration: const InputDecoration(labelText: 'Nom du produit')),
          TextField(controller: categorie, decoration: const InputDecoration(labelText: 'Catégorie')),
          TextField(controller: reference, decoration: const InputDecoration(labelText: 'Référence (facultative)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, nom.text.trim().length >= 2), child: const Text('Ajouter')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await supabase.rpc('enregistrer_produit', params: {
        'p_nom': nom.text.trim(),
        'p_categorie': categorie.text.trim(),
        'p_reference': reference.text.trim().isEmpty ? null : reference.text.trim(),
      });
      setState(() => _cle++);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ajout impossible : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    return Scaffold(
      backgroundColor: const Color(0xff0a3d24),
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 12, 18),
          child: Row(children: [
            Expanded(child: Text('Bonjour, ${session?.nom ?? 'Fabricant'}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700))),
            IconButton(color: Colors.white, tooltip: 'Actualiser', onPressed: () => setState(() => _cle++), icon: const Icon(Icons.refresh)),
            IconButton(color: Colors.white, onPressed: () => ref.read(authProvider).deconnecter(), icon: const Icon(Icons.logout)),
          ]),
        ),
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              color: Jetons.creme,
              borderRadius: BorderRadius.vertical(top: Radius.circular(Jetons.rFeuille)),
            ),
            clipBehavior: Clip.antiAlias,
            child: IndexedStack(index: _onglet, children: [
              _ApercuFabricant(future: _apercu(), cle: _cle),
              _Catalogue(future: _catalogue(), cle: _cle, onAdd: _ajouterProduit),
              _Ruptures(future: _ruptures()),
              RetoursRecusTab(cle: _cle, fabricant: true),
            ]),
          ),
        ),
      ])),
      bottomNavigationBar: NavigationBar(selectedIndex: _onglet, onDestinationSelected: (i) => setState(() => _onglet = i), destinations: const [
        NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), label: 'Aperçu'),
        NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Catalogue'),
        NavigationDestination(icon: Icon(Icons.warning_amber_outlined), label: 'Ruptures'),
        NavigationDestination(icon: Icon(Icons.forum_outlined), label: 'Retours'),
      ]),
    );
  }
}

class _Catalogue extends StatelessWidget {
  const _Catalogue({required this.future, required this.cle, required this.onAdd});
  final Future<List<Map<String, dynamic>>> future;
  final int cle;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    key: ValueKey(cle), future: future, builder: (context, snap) {
      if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) return Center(child: Text('Catalogue indisponible : ${snap.error}'));
      final rows = snap.data ?? const [];
      return Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [const Expanded(child: Text('Mon catalogue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))), FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Produit'))])),
        Expanded(child: ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: rows.length, itemBuilder: (context, i) {
          final p = rows[i];
          return Card(child: ListTile(leading: VignetteProduit(nom: p['nom'] as String? ?? '', imageUrl: p['image_url'] as String?, categorie: p['categorie'] as String?, taille: 48), title: Text(p['nom'] as String? ?? ''), subtitle: Text('${p['reference'] ?? ''} · ${p['boutiques_suivant'] ?? 0} boutique(s)')));
        })),
      ]);
    },
  );
}

class _Ruptures extends StatelessWidget {
  const _Ruptures({required this.future});
  final Future<List<Map<String, dynamic>>> future;
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(future: future, builder: (context, snap) {
    if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
    if (snap.hasError) return Center(child: Text('Ruptures indisponibles : ${snap.error}'));
    final rows = snap.data ?? const [];
    if (rows.isEmpty) return const Center(child: Text('Aucune rupture sur votre catalogue'));
    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: rows.length, itemBuilder: (context, i) {
      final r = rows[i];
      return Card(child: ListTile(leading: VignetteProduit(nom: r['produit'] as String? ?? '', imageUrl: r['image_url'] as String?, categorie: r['categorie'] as String?, taille: 48), title: Text(r['produit'] as String? ?? ''), subtitle: Text('${r['point_de_vente'] ?? ''} · ${r['commune'] ?? ''}'), trailing: Text('${r['quantite_demandee'] ?? 0}')));
    });
  });
}
