import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import 'caisse_tab.dart';
import 'stock_tab.dart';

/// Interface du point de vente : la caisse et le stock.
///
/// L'ordre des onglets n'est pas anodin. La caisse vient en premier parce que
/// c'est ce que le boutiquier ouvre tous les jours, et que c'est le service
/// qu'on lui rend. Le signalement de rupture, lui, est relégué dans l'onglet
/// Stock, parce qu'en régime normal il n'a pas à s'en servir : la vente qui
/// vide son rayon prévient déjà son distributeur.
///
/// C'est tout le pari du produit. Un boutiquier n'a aucune raison spontanée de
/// déclarer ses ruptures. Une caisse gratuite lui donne une raison d'ouvrir
/// l'application, et le signalement devient un effet de bord de son encaissement.
class PointDeVenteHomeScreen extends ConsumerStatefulWidget {
  const PointDeVenteHomeScreen({super.key, required this.pointDeVenteId});

  final String pointDeVenteId;

  @override
  ConsumerState<PointDeVenteHomeScreen> createState() => _PointDeVenteHomeScreenState();
}

class _PointDeVenteHomeScreenState extends ConsumerState<PointDeVenteHomeScreen> {
  int _onglet = 0;

  /// Incrémentée après chaque encaissement. L'onglet Stock l'observe et se
  /// recharge : c'est à cet instant qu'une rupture a pu naître toute seule.
  int _cleRafraichissement = 0;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(session?.nom ?? 'Ma boutique'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Se déconnecter',
            onPressed: () => ref.read(authProvider).deconnecter(),
          ),
        ],
      ),
      body: IndexedStack(
        index: _onglet,
        children: [
          CaisseTab(
            onVenteEnregistree: () => setState(() => _cleRafraichissement++),
          ),
          StockTab(
            pointDeVenteId: widget.pointDeVenteId,
            cle: _cleRafraichissement,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _onglet,
        onDestinationSelected: (i) => setState(() => _onglet = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale),
            label: 'Caisse',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Stock',
          ),
        ],
      ),
    );
  }
}
