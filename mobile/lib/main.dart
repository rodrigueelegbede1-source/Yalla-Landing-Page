import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/auth/auth_providers.dart';
import 'features/auth/login_screen.dart';
import 'features/administrateur/administrateur_home_screen.dart';
import 'features/fabricant/fabricant_home_screen.dart';
import 'features/livreur/livreur_home_screen.dart';
import 'features/point_de_vente/point_de_vente_home_screen.dart';
import 'features/agent_recenseur/agent_recenseur_home_screen.dart';

void main() {
  runApp(const ProviderScope(child: YallaApp()));
}

class YallaApp extends StatelessWidget {
  const YallaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yalla',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF0E7C7B), useMaterial3: true),
      home: const _EcranRacine(),
    );
  }
}

/// Aiguille vers l'écran de connexion ou vers l'accueil du rôle une fois
/// connecté. Volontairement simple pour ce squelette — un routage plus
/// riche (go_router, deep links, navigation imbriquée par onglet à
/// l'intérieur de chaque interface) peut se greffer ici une fois les 5
/// interfaces développées au-delà de leur écran d'accueil.
///
/// `session.role` distingue l'interface à afficher, et `session.idMetier`
/// (fabricantId / livreurId / pointDeVenteId, renvoyé directement par
/// POST /auth/login) est transmis à l'écran correspondant.
class _EcranRacine extends ConsumerWidget {
  const _EcranRacine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    if (session.enCoursDeChargement) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!session.estConnecte) {
      return const LoginScreen();
    }

    switch (session.role) {
      case 'administrateur':
        return const AdministrateurHomeScreen();
      case 'fabricant':
        return FabricantHomeScreen(fabricantId: session.idMetier ?? '');
      case 'livreur':
        return LivreurHomeScreen(livreurId: session.idMetier ?? '');
      case 'point_de_vente':
        return PointDeVenteHomeScreen(pointDeVenteId: session.idMetier ?? '');
      case 'agent_recenseur':
        return const AgentRecenseurHomeScreen();
      default:
        return const LoginScreen();
    }
  }
}
