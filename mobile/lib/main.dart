import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_providers.dart';
import 'core/supabase.dart';
import 'features/auth/login_screen.dart';
import 'features/distributeur/distributeur_home_screen.dart';
import 'features/livreur/livreur_home_screen.dart';
import 'features/point_de_vente/point_de_vente_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initialiserSupabase();
  runApp(const ProviderScope(child: YallaApp()));
}

class YallaApp extends StatelessWidget {
  const YallaApp({super.key});

  // Charte de la maquette : vert profond et jaune signalétique.
  static const _vert = Color(0xFF146B3A);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yalla',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _vert, useMaterial3: true),
      home: const _EcranRacine(),
    );
  }
}

/// Aiguille vers l'écran du rôle, ou vers la connexion.
///
/// Le MVP ne couvre que trois rôles : Point de vente, Distributeur et Livreur.
/// C'est la boucle qui fait la différence du produit — une vente vide un stock,
/// la rupture part toute seule, quelqu'un livre. Les trois autres rôles
/// existent en base et dans les maquettes, mais pas encore ici, et l'écran le
/// dit franchement plutôt que d'afficher une page vide.
class _EcranRacine extends ConsumerWidget {
  const _EcranRacine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return session.when(
      loading: () => const _EcranAttente(),
      error: (e, _) => const _EcranMessage(
        icone: Icons.cloud_off_outlined,
        titre: 'Connexion impossible',
        message: 'Impossible de joindre Yalla. Vérifiez votre réseau, '
            'puis relancez l\'application.',
      ),
      data: (s) {
        if (!s.estConnecte) return const LoginScreen();

        if (s.rattachementIncomplet) {
          return const _EcranMessage(
            icone: Icons.person_off_outlined,
            titre: 'Compte incomplet',
            message: 'Votre compte existe mais n\'est rattaché à aucune boutique, '
                'ni à aucun distributeur. Contactez la personne qui vous a remis '
                'vos identifiants.',
            deconnexion: true,
          );
        }

        switch (s.role) {
          case 'point_de_vente':
            return PointDeVenteHomeScreen(pointDeVenteId: s.idMetier!);
          case 'distributeur':
            return DistributeurHomeScreen(distributeurId: s.idMetier!);
          case 'livreur':
            return LivreurHomeScreen(livreurId: s.idMetier!);
          default:
            return _EcranMessage(
              icone: Icons.construction_outlined,
              titre: 'Interface en construction',
              message: 'Le rôle « ${s.role} » n\'est pas encore disponible dans '
                  'l\'application. La première version couvre les boutiques, '
                  'les distributeurs et les livreurs.',
              deconnexion: true,
            );
        }
      },
    );
  }
}

class _EcranAttente extends StatelessWidget {
  const _EcranAttente();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _EcranMessage extends ConsumerWidget {
  const _EcranMessage({
    required this.icone,
    required this.titre,
    required this.message,
    this.deconnexion = false,
  });

  final IconData icone;
  final String titre;
  final String message;
  final bool deconnexion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icone, size: 56),
                const SizedBox(height: 24),
                Text(titre,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, height: 1.5)),
                if (deconnexion) ...[
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('Se déconnecter'),
                    onPressed: () => ref.read(authProvider).deconnecter(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
