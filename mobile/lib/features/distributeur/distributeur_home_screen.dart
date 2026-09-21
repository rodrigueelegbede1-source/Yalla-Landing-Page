import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/coque.dart';
import '../../core/theme.dart';
import '../../core/temps_reel.dart';
import '../../core/widgets.dart';
import 'carnet_tab.dart';
import 'flotte_tab.dart';
import 'reseau_tab.dart';

/// Le distributeur, en trois onglets.
///
/// Il n'en avait qu'un, le carnet, et cela le laissait dans une impasse : il
/// voyait des courses mais n'avait aucun livreur à qui les donner, et aucun
/// moyen de déclarer les boutiques qu'il dessert. Or c'est cette déclaration
/// qui décide du destinataire d'une rupture. Sans elle, le cercle « attribué »,
/// qui est le cœur du modèle, n'existait tout simplement pas.
///
///   * **Courses** : le carnet, en deux cercles, qui se réveille tout seul.
///   * **Flotte** : ses livreurs, et la création de leurs comptes.
///   * **Réseau** : ses marques et ses boutiques.
class DistributeurHomeScreen extends ConsumerStatefulWidget {
  const DistributeurHomeScreen({super.key, required this.distributeurId});

  final String distributeurId;

  @override
  ConsumerState<DistributeurHomeScreen> createState() =>
      _DistributeurHomeScreenState();
}

class _DistributeurHomeScreenState extends ConsumerState<DistributeurHomeScreen> {
  int _onglet = 0;

  /// Rechargements croisés : affecter une course change aussi la flotte, dont
  /// le compteur de courses en cours.
  int _cleCarnet = 0;
  int _cleFlotte = 0;
  int _cleReseau = 0;

  int _revisionVue = 0;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    final signal = ref.watch(tempsReelCoursesProvider);

    // LE BRANCHEMENT QUI MANQUAIT. La publication temps réel existait côté base
    // depuis la migration `realtime_et_cron`, mais rien ne s'y abonnait : le
    // carnet ne bougeait qu'en tirant la liste vers le bas. Sur une rupture,
    // ce délai est le produit lui-même.
    if (signal.revision != _revisionVue) {
      _revisionVue = signal.revision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _cleCarnet++;
          _cleFlotte++;
        });
      });
    }

    return Scaffold(
      backgroundColor: Jetons.vert800,
      body: CoqueVerte(
        entete: SalutationCanevas(
          salutation: 'Bonjour,',
          nom: session?.nom ?? 'Distributeur',
          detail: 'Vos courses, votre flotte et vos boutiques.',
          actions: [
            PastilleTempsReel(connecte: signal.connecte, surVert: true),
            BoutonCanevas(
              icone: Icons.logout,
              infobulle: 'Se déconnecter',
              onTap: () => ref.read(authProvider).deconnecter(),
            ),
          ],
        ),
        enfant: IndexedStack(
          index: _onglet,
          children: [
            CarnetTab(
              cle: _cleCarnet,
              onChangement: () => setState(() => _cleFlotte++),
            ),
            FlotteTab(cle: _cleFlotte),
            ReseauTab(cle: _cleReseau),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _onglet,
        onDestinationSelected: (i) {
          setState(() {
            _onglet = i;
            // Le réseau ne bouge pas tout seul : on le recharge à l'ouverture
            // de l'onglet plutôt que de l'abonner au temps réel pour rien.
            if (i == 2) _cleReseau++;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Courses',
          ),
          NavigationDestination(
            icon: Icon(Icons.two_wheeler_outlined),
            selectedIcon: Icon(Icons.two_wheeler),
            label: 'Flotte',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Réseau',
          ),
        ],
      ),
    );
  }
}
