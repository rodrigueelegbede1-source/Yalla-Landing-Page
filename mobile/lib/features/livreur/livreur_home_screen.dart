import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/coque.dart';
import '../../core/theme.dart';
import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/temps_reel.dart';
import 'courses_tab.dart';
import 'livraison_tab.dart';
import 'suivi_position.dart';

/// Interface du livreur : les courses disponibles, et celles qu'il a prises.
///
/// Deux choses ont changé ici, et ce sont les deux qui séparaient une maquette
/// d'un outil de terrain :
///
///   * la position est portée par [SuiviPosition], qui tient un service de
///     premier plan. Le livreur peut ranger son téléphone, le distributeur
///     continue de le voir avancer ;
///   * les listes se réveillent seules. Une course affectée par le
///     distributeur apparaît sans que le livreur touche à rien, ce qui est le
///     seul comportement acceptable pour quelqu'un qui conduit.
class LivreurHomeScreen extends ConsumerStatefulWidget {
  const LivreurHomeScreen({super.key, required this.livreurId});

  final String livreurId;

  @override
  ConsumerState<LivreurHomeScreen> createState() => _LivreurHomeScreenState();
}

class _LivreurHomeScreenState extends ConsumerState<LivreurHomeScreen> {
  late final SuiviPosition _suivi = SuiviPosition(livreurId: widget.livreurId);

  int _onglet = 0;
  bool _enLigne = false;

  /// Incrémentées pour forcer le rechargement croisé des deux onglets : une
  /// course prise disparaît de la première liste et apparaît dans la seconde,
  /// une course abandonnée fait le trajet inverse.
  int _cleCourses = 0;
  int _cleLivraisons = 0;

  /// La dernière révision temps réel déjà répercutée, pour ne pas recharger
  /// deux fois le même évènement.
  int _revisionVue = 0;

  @override
  void initState() {
    super.initState();
    _suivi.addListener(_surSuivi);
    _lireEtatEnLigne();
  }

  @override
  void dispose() {
    _suivi.removeListener(_surSuivi);
    _suivi.dispose();
    super.dispose();
  }

  void _surSuivi() {
    if (mounted) setState(() {});
  }

  Future<void> _lireEtatEnLigne() async {
    try {
      final ligne = await supabase
          .from('livreurs')
          .select('en_ligne')
          .eq('id', widget.livreurId)
          .single();
      if (!mounted) return;
      final enLigne = ligne['en_ligne'] == true;
      setState(() => _enLigne = enLigne);
      // Reprise après une fermeture brutale de l'application : la base le croit
      // encore en service, on redémarre donc le suivi pour que ce soit vrai.
      if (enLigne) await _suivi.demarrer();
    } catch (_) {
      // Sans cette lecture, l'interrupteur part simplement à « hors ligne ».
    }
  }

  /// L'interrupteur qui met le livreur en service.
  ///
  /// Il fait les deux choses à la fois, et c'est volontaire : être en ligne
  /// sans partager sa position n'a aucun sens pour le distributeur, qui affecte
  /// ses courses à la moto la plus proche. Un seul geste, une seule promesse.
  Future<void> _basculerEnLigne(bool valeur) async {
    setState(() => _enLigne = valeur);

    if (valeur) {
      await _suivi.demarrer();
      if (!_suivi.actif) {
        // La permission a été refusée : on ne laisse pas l'interrupteur mentir.
        if (mounted) setState(() => _enLigne = false);
        return;
      }
    } else {
      await _suivi.arreter();
    }

    try {
      await supabase
          .from('livreurs')
          .update({'en_ligne': valeur})
          .eq('id', widget.livreurId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _enLigne = !valeur);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(messageErreur(context, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    final signal = ref.watch(tempsReelCoursesProvider);

    // Une modification reçue en direct recharge les deux onglets. Le
    // rechargement passe par la vue, qui est sous RLS : rien ne peut arriver
    // ici que le livreur n'ait le droit de voir.
    if (signal.revision != _revisionVue) {
      _revisionVue = signal.revision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _cleCourses++;
          _cleLivraisons++;
        });
      });
    }

    // LE LIVREUR EST LE SEUL À GARDER SON INTERRUPTEUR DANS LE CANEVAS. Être en
    // service ou non décide de tout ce qu'il voit, et ce n'est pas un réglage
    // rangé dans un menu : c'est l'état dans lequel il se trouve. Il est donc
    // posé dans le vert, à hauteur de pouce, avec son libellé en clair.
    return Scaffold(
      backgroundColor: Jetons.vert800,
      body: CoqueVerte(
        entete: Column(
          children: [
            SalutationCanevas(
              salutation: _enLigne ? 'En service' : 'Hors service',
              nom: session?.nom ?? 'Livreur',
              actions: [
                _PastilleTempsReel(connecte: signal.connecte),
                BoutonCanevas(
                  icone: Icons.logout,
                  infobulle: 'Se déconnecter',
                  onTap: () async {
                    await _suivi.arreter();
                    if (!context.mounted) return;
                    await ref.read(authProvider).deconnecter();
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 22),
              child: Container(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 8, 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _enLigne
                            ? 'Vous recevez les courses proches'
                            : 'Vous ne recevez aucune course',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Colors.white.withValues(alpha: .88),
                        ),
                      ),
                    ),
                    Switch(
                      value: _enLigne,
                      onChanged: _basculerEnLigne,
                      activeThumbColor: Jetons.vert900,
                      activeTrackColor: Jetons.jaune,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        enfant: Column(
          children: [
            _BandeauSuivi(suivi: _suivi, enLigne: _enLigne),
            Expanded(
              child: IndexedStack(
                index: _onglet,
                children: [
                  CoursesTab(
                    cle: _cleCourses,
                    onCoursePrise: () => setState(() => _cleLivraisons++),
                  ),
                  LivraisonTab(
                    cle: _cleLivraisons,
                    onChangement: () => setState(() => _cleCourses++),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _onglet,
        onDestinationSelected: (i) => setState(() => _onglet = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.near_me_outlined),
            selectedIcon: Icon(Icons.near_me),
            label: 'À proximité',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping),
            label: 'Mes courses',
          ),
        ],
      ),
    );
  }
}

/// L'état du suivi, dit franchement.
///
/// Un livreur qui croit être suivi alors qu'il ne l'est pas prend des courses
/// qu'on ne lui attribuera jamais, et un distributeur qui voit une moto figée
/// appelle pour rien. Chaque état a donc son message et son geste de sortie.
class _BandeauSuivi extends StatelessWidget {
  const _BandeauSuivi({required this.suivi, required this.enLigne});

  final SuiviPosition suivi;
  final bool enLigne;

  @override
  Widget build(BuildContext context) {
    if (!enLigne && suivi.etat == EtatSuivi.arrete) {
      return const _Bandeau(
        icone: Icons.toggle_off_outlined,
        texte: 'Vous êtes hors service. Mettez-vous en ligne pour recevoir des courses.',
        couleur: Colors.blueGrey,
      );
    }

    switch (suivi.etat) {
      case EtatSuivi.refuse:
        return _Bandeau(
          icone: Icons.location_off_outlined,
          texte: suivi.erreur ??
              'Sans votre position, les courses ne peuvent pas être triées par distance.',
          couleur: Colors.orange,
          action: 'Autoriser',
          onAction: () => suivi.demarrer(),
        );

      case EtatSuivi.refuseDefinitivement:
        return _Bandeau(
          icone: Icons.block_outlined,
          texte: 'La localisation est bloquée pour Yalla. Rétablissez-la dans '
              'les réglages du téléphone.',
          couleur: Colors.red,
          action: 'Réglages',
          onAction: suivi.ouvrirReglages,
        );

      case EtatSuivi.premierPlan:
        return _Bandeau(
          icone: Icons.my_location_outlined,
          texte: 'Suivi actif, mais seulement application ouverte. Téléphone en '
              'poche, votre distributeur ne vous verra plus avancer.',
          couleur: Colors.orange,
          action: 'Activer en fond',
          onAction: () => suivi.demarrer(),
        );

      case EtatSuivi.arrierePlan:
        final envoi = suivi.dernierEnvoi;
        return _Bandeau(
          icone: Icons.gps_fixed,
          texte: envoi == null
              ? 'Suivi en cours, première position en attente.'
              : 'Suivi en cours, position transmise il y a '
                  '${depuis(DateTime.now().difference(envoi).inSeconds)}.',
          couleur: Colors.green,
        );

      case EtatSuivi.arrete:
        return const SizedBox.shrink();
    }
  }
}

class _Bandeau extends StatelessWidget {
  const _Bandeau({
    required this.icone,
    required this.texte,
    required this.couleur,
    this.action,
    this.onAction,
  });

  final IconData icone;
  final String texte;
  final Color couleur;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: couleur.withValues(alpha: 0.10),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(icone, size: 18, color: couleur),
            const SizedBox(width: 10),
            Expanded(
              child: Text(texte, style: const TextStyle(fontSize: 12, height: 1.35)),
            ),
            if (action != null)
              TextButton(onPressed: onAction, child: Text(action!)),
          ],
        ),
      );
}

/// Dit si la liste est vivante ou figée. Discret, mais c'est la différence
/// entre « aucune course » et « aucune nouvelle reçue ».
class _PastilleTempsReel extends StatelessWidget {
  const _PastilleTempsReel({required this.connecte});
  final bool connecte;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: connecte
            ? 'Mise à jour en direct'
            : 'Hors direct, tirez la liste pour rafraîchir',
        child: Icon(
          connecte ? Icons.bolt : Icons.bolt_outlined,
          size: 18,
          color: connecte ? Colors.green : Colors.grey,
        ),
      );
}
