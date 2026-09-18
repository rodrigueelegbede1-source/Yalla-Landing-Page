import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_providers.dart';
import 'core/langue.dart';
import 'core/supabase.dart';
import 'l10n/app_localizations.dart';
import 'features/agent_recenseur/recensement_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/distributeur/distributeur_home_screen.dart';
import 'features/livreur/livreur_home_screen.dart';
import 'features/point_de_vente/point_de_vente_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initialiserSupabase();
  runApp(const ProviderScope(child: YallaApp()));
}

class YallaApp extends ConsumerWidget {
  const YallaApp({super.key});

  // Charte de la maquette : vert profond et jaune signalétique.
  static const _vert = Color(0xFF146B3A);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Yalla',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _vert, useMaterial3: true),

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
/// Quatre rôles sur six. Aux trois de la boucle centrale, Point de vente,
/// Distributeur et Livreur, s'ajoute l'agent recenseur.
///
/// Il avait été écarté du périmètre, et c'était une erreur : sans lui, chaque
/// boutique du pilote demandait deux `INSERT` SQL et un appel à l'API
/// d'administration, tapés à la main. Le périmètre était juste sur le papier et
/// faux sur le terrain, puisqu'il rendait le terrain inatteignable.
///
/// Restent dehors le fabricant et l'administrateur, qui sont deux tableaux de
/// bord en lecture. Ils ne bloquent rien, et l'écran le dit franchement plutôt
/// que d'afficher une page vide.
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
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
