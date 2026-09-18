import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/langue.dart';
import '../../core/supabase.dart';
import '../../core/temps_reel.dart';
import '../../core/widgets.dart';
import '../../l10n/app_localizations.dart';
import 'caisse_tab.dart';
import 'catalogue_tab.dart';
import 'confirmation_tab.dart';
import 'stock_tab.dart';

/// Interface du point de vente : la caisse, le stock, le catalogue et les
/// demandes à confirmer.
///
/// L'ORDRE DES ONGLETS N'EST PAS ANODIN. La caisse vient en premier parce que
/// c'est ce que le boutiquier ouvre tous les jours, et que c'est le service
/// qu'on lui rend. Le catalogue vient juste après, parce que celui qui
/// n'utilise pas la caisse n'a que lui pour demander quoi que ce soit : le
/// reléguer en dernier reviendrait à ne rien proposer à cette moitié-là.
///
/// LA CONFIRMATION S'OUVRE D'ELLE-MÊME APRÈS UN ENCAISSEMENT qui a vidé un
/// stock. C'est la seule façon de rendre ce geste quasi gratuit : le boutiquier
/// tient encore son téléphone, il vient d'appuyer sur « Encaisser », et la
/// demande arrive dans la seconde. Attendre qu'il pense à ouvrir un onglet,
/// c'est accepter que la rupture ne parte jamais.
///
/// Le compteur reste ensuite visible en permanence sur l'onglet, parce qu'un
/// boutiquier interrompu par un client ne reviendra pas de lui-même.
class PointDeVenteHomeScreen extends ConsumerStatefulWidget {
  const PointDeVenteHomeScreen({super.key, required this.pointDeVenteId});

  final String pointDeVenteId;

  @override
  ConsumerState<PointDeVenteHomeScreen> createState() =>
      _PointDeVenteHomeScreenState();
}

class _PointDeVenteHomeScreenState extends ConsumerState<PointDeVenteHomeScreen> {
  int _onglet = 0;

  /// Incrémentée après chaque encaissement. Les autres onglets l'observent et
  /// se rechargent : c'est à cet instant qu'une rupture a pu naître toute seule.
  int _cleRafraichissement = 0;

  int _aConfirmer = 0;
  int _revisionVue = 0;

  @override
  void initState() {
    super.initState();
    _compterAConfirmer();
  }

  Future<void> _compterAConfirmer() async {
    try {
      final lignes = await supabase
          .from('v_ruptures_a_confirmer')
          .select('rupture_id')
          .count();
      if (mounted) setState(() => _aConfirmer = lignes.count);
    } catch (_) {
      // Sans ce compteur, l'onglet n'affiche simplement pas de pastille.
    }
  }

  /// Après un encaissement, on bascule sur les demandes s'il y en a de
  /// nouvelles. Sinon on reste sur la caisse : interrompre un boutiquier qui
  /// enchaîne les clients pour lui montrer une liste vide serait une nuisance.
  Future<void> _apresVente() async {
    setState(() => _cleRafraichissement++);
    final avant = _aConfirmer;
    await _compterAConfirmer();
    if (!mounted) return;
    if (_aConfirmer > avant) setState(() => _onglet = 3);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final session = ref.watch(sessionProvider).value;
    final signal = ref.watch(tempsReelBoutiqueProvider);

    // Une livraison qui reconstitue le stock arrive par le temps réel : c'est
    // le seul moment où le produit se montre au boutiquier sans qu'il agisse.
    if (signal.revision != _revisionVue) {
      _revisionVue = signal.revision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _cleRafraichissement++);
        _compterAConfirmer();
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(session?.nom ?? l.appNom),
        actions: [
          PastilleTempsReel(connecte: signal.connecte),
          const BoutonLangue(),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l.seDeconnecter,
            onPressed: () => ref.read(authProvider).deconnecter(),
          ),
        ],
      ),
      body: IndexedStack(
        index: _onglet,
        children: [
          CaisseTab(onVenteEnregistree: _apresVente),
          CatalogueTab(
            cle: _cleRafraichissement,
            onChangement: () {
              setState(() => _cleRafraichissement++);
              _compterAConfirmer();
            },
          ),
          StockTab(
            pointDeVenteId: widget.pointDeVenteId,
            cle: _cleRafraichissement,
          ),
          ConfirmationTab(
            cle: _cleRafraichissement,
            onChangement: () {
              setState(() => _cleRafraichissement++);
              _compterAConfirmer();
            },
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _onglet,
        onDestinationSelected: (i) => setState(() => _onglet = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.point_of_sale_outlined),
            selectedIcon: const Icon(Icons.point_of_sale),
            label: l.ongletCaisse,
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: const Icon(Icons.menu_book),
            label: l.ongletCatalogue,
          ),
          NavigationDestination(
            icon: const Icon(Icons.inventory_2_outlined),
            selectedIcon: const Icon(Icons.inventory_2),
            label: l.ongletStock,
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _aConfirmer > 0,
              label: Text('$_aConfirmer'),
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: _aConfirmer > 0,
              label: Text('$_aConfirmer'),
              child: const Icon(Icons.notifications),
            ),
            label: l.aConfirmerTitre,
          ),
        ],
      ),
    );
  }
}
