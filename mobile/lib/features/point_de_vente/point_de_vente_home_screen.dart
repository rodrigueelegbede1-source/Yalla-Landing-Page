import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/coque.dart';
import '../../core/langue.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../core/temps_reel.dart';
import '../../core/widgets.dart';
import '../../l10n/app_localizations.dart';
import 'catalogue_tab.dart';
import 'messages_tab.dart';
import 'retours_tab.dart';

/// Interface boutique : catalogue de signalement, communications et retours terrain.
class PointDeVenteHomeScreen extends ConsumerStatefulWidget {
  const PointDeVenteHomeScreen({super.key, required this.pointDeVenteId});

  final String pointDeVenteId;

  @override
  ConsumerState<PointDeVenteHomeScreen> createState() =>
      _PointDeVenteHomeScreenState();
}

class _PointDeVenteHomeScreenState extends ConsumerState<PointDeVenteHomeScreen> {
  int _onglet = 0;

  int _cleRafraichissement = 0;

  int _revisionVue = 0;

  /// Messages non lus SUR CE TÉLÉPHONE.
  ///
  /// Rien ne trace la lecture côté base, et le tableau de bord de
  /// l'administrateur écrit « non suivi » plutôt qu'un pourcentage inventé. Ce
  /// compteur est donc une commodité locale, pas une mesure : il compare la
  /// date du dernier message à celle de la dernière ouverture de l'onglet,
  /// gardée dans les préférences de l'appareil. Réinstaller l'application le
  /// remet à zéro, et c'est sans conséquence.
  int _messagesNonLus = 0;
  static const _cleDerniereLecture = 'yalla.messages.derniere_lecture';

  @override
  void initState() {
    super.initState();
    _compterMessages();
  }

  Future<void> _compterMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final depuis = prefs.getString(_cleDerniereLecture);

      var requete = supabase.from('v_mes_diffusions').select('diffusion_id');
      if (depuis != null) requete = requete.gt('date_envoi', depuis);

      final lignes = await requete.count();
      if (mounted) setState(() => _messagesNonLus = lignes.count);
    } catch (_) {
      // Sans ce compteur, l'onglet n'affiche simplement pas de pastille. Ce
      // n'est pas une raison d'empêcher le boutiquier de parcourir le catalogue.
    }
  }

  /// Ouvrir l'onglet vaut lecture. On enregistre l'instant plutôt que la date
  /// du dernier message : si un message arrive pendant qu'il lit, il ne sera
  /// pas passé pour lu.
  Future<void> _marquerMessagesLus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _cleDerniereLecture, DateTime.now().toUtc().toIso8601String());
      if (mounted) setState(() => _messagesNonLus = 0);
    } catch (_) {
      if (mounted) setState(() => _messagesNonLus = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final session = ref.watch(sessionProvider).value;
    final signal = ref.watch(tempsReelBoutiqueProvider);

    // Les mises à jour du réseau rafraîchissent le catalogue et les messages.
    if (signal.revision != _revisionVue) {
      _revisionVue = signal.revision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _cleRafraichissement++);
        _compterMessages();
      });
    }

    // LA COQUE DE LA RÉFÉRENCE, ET CE QU'ON N'EN PREND PAS.
    //
    // On reprend le canevas vert et la feuille blanche qui le chevauche : ils
    // donnent au contenu une frontière franche sans tracer un filet, ce qui
    // tient au soleil là où un gris clair disparaît.
    //
    final enAttente = _messagesNonLus;

    return Scaffold(
      backgroundColor: Jetons.vert800,
      body: CoqueVerte(
        entete: SalutationCanevas(
          salutation: l.salutation,
          nom: session?.nom ?? l.appNom,
            detail: enAttente == 0 ? l.rienEnAttente : l.enAttenteResume(0, _messagesNonLus),
          actions: [
            PastilleTempsReel(connecte: signal.connecte, surVert: true),
            const BoutonLangue(surVert: true),
            BoutonCanevas(
              icone: Icons.logout,
              infobulle: l.seDeconnecter,
              onTap: () => ref.read(authProvider).deconnecter(),
            ),
          ],
        ),
        enfant: IndexedStack(
        index: _onglet,
        children: [
          CatalogueTab(
            cle: _cleRafraichissement,
            onChangement: () => setState(() => _cleRafraichissement++),
          ),
          MessagesTab(
            cle: _cleRafraichissement,
            onChangement: () => setState(() => _cleRafraichissement++),
          ),
          RetoursTab(
            cle: _cleRafraichissement,
            onChangement: () => setState(() => _cleRafraichissement++),
          ),
        ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _onglet,
        onDestinationSelected: (i) {
          setState(() => _onglet = i);
          if (i == 1) _marquerMessagesLus();
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: const Icon(Icons.menu_book),
            label: l.ongletCatalogue,
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _messagesNonLus > 0,
              label: Text('$_messagesNonLus'),
              child: const Icon(Icons.mail_outline),
            ),
            selectedIcon: Badge(
              isLabelVisible: _messagesNonLus > 0,
              label: Text('$_messagesNonLus'),
              child: const Icon(Icons.mail),
            ),
            label: l.ongletMessages,
          ),
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: Localizations.localeOf(context).languageCode == 'ar' ? 'الملاحظات' : 'Retours',
          ),
        ],
      ),
    );
  }
}
