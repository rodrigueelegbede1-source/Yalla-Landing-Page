import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_providers.dart';
import 'core/langue.dart';
import 'core/theme.dart';
import 'core/supabase.dart';
import 'l10n/app_localizations.dart';
import 'features/agent_recenseur/recensement_screen.dart';
import 'features/administrateur/administrateur_home_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/distributeur/distributeur_home_screen.dart';
import 'features/fabricant/fabricant_home_screen.dart';
import 'features/livreur/livreur_home_screen.dart';
import 'features/point_de_vente/point_de_vente_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initialiserSupabase();
  runApp(const ProviderScope(child: YallaApp()));
}

class YallaApp extends ConsumerWidget {
  const YallaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Yalla',
      debugShowCheckedModeBanner: false,
      // Le système visuel vit dans core/theme.dart. Une graine de couleur
      // laissait Material 3 déduire tout le reste, ce qui donnait une
      // application correcte et anonyme : ni le jaune du logo, ni les rayons,
      // ni l'échelle typographique n'en sortaient.
      theme: themeYalla(),

      // Français et arabe. La locale nulle laisse Flutter suivre le téléphone,
      // ce qui est le bon défaut tant que l'utilisateur n'a rien choisi.
      //
      // L'arabe bascule toute l'interface en droite-à-gauche, sans rien à faire
      // ici : Flutter lit le sens dans la locale. C'est dans les écrans que la
      // règle se tient, en n'utilisant que des marges logiques (`start` /
      // `end`) et jamais `left` ni `right`.
      locale: ref.watch(langueProvider),
      supportedLocales: ChoixLangue.supportees,
      localizationsDelegates: const [
        L.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      home: const _EcranRacine(),
    );
  }
}

/// Aiguille vers l'écran du rôle, ou vers la connexion.
///
/// Les six rôles sont maintenant aiguillés dans l'application :
/// point de vente, fabricant, distributeur, livreur, agent recenseur et
/// administrateur. Les droits réels restent décidés par les politiques RLS et
/// les fonctions SQL, jamais par ce switch d'interface.
class _EcranRacine extends ConsumerWidget {
  const _EcranRacine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final l = L.of(context);

    return session.when(
      loading: () => const _EcranAttente(),
      error: (e, _) => _EcranMessage(
        icone: Icons.cloud_off_outlined,
        titre: l.connexionImpossible,
        message: l.connexionImpossibleMessage,
      ),
      data: (s) {
        if (!s.estConnecte) return const LoginScreen();

        if (s.rattachementIncomplet) {
          return _EcranMessage(
            icone: Icons.person_off_outlined,
            titre: l.compteIncomplet,
            message: l.compteIncompletMessage,
            deconnexion: true,
          );
        }

        switch (s.role) {
          case 'administrateur':
            return const AdministrateurHomeScreen();
          case 'fabricant':
            return FabricantHomeScreen(fabricantId: s.idMetier!);
          case 'point_de_vente':
            return PointDeVenteHomeScreen(pointDeVenteId: s.idMetier!);
          case 'distributeur':
            return DistributeurHomeScreen(distributeurId: s.idMetier!);
          case 'livreur':
            return LivreurHomeScreen(livreurId: s.idMetier!);
          case 'agent_recenseur':
            return AgentRecenseurHomeScreen(agentId: s.idMetier!);
          default:
            return _EcranMessage(
              icone: Icons.construction_outlined,
              titre: l.roleEnConstruction,
              message: l.roleEnConstructionMessage(s.role ?? ''),
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
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, height: 1.5)),
                const SizedBox(height: 24),
                const BoutonLangue(),
                if (deconnexion) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.logout),
                    label: Text(L.of(context).seDeconnecter),
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
