
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';

/// La langue de l'application, et le sens de lecture qui va avec.
///
/// POURQUOI L'ARABE N'EST PAS UNE TRADUCTION DE PLUS. Une part importante des
/// boutiquiers de proximité d'Abidjan lisent et écrivent l'arabe plus
/// couramment que le français. Leur donner l'application dans leur langue
/// change qui peut s'en servir sans aide, ce qui est exactement la différence
/// entre un outil adopté et un outil abandonné au bout d'une semaine.
///
/// L'arabe entraîne le passage en droite-à-gauche, et ce n'est pas un détail
/// d'affichage : toute la disposition s'inverse. Flutter s'en charge dès que la
/// locale est posée, à condition que l'interface ait été écrite avec des marges
/// logiques (`start` / `end`) et non physiques (`left` / `right`). C'est la
/// règle à tenir dans tous les écrans.
///
/// LES CHIFFRES RESTENT EN ÉCRITURE OCCIDENTALE, y compris en arabe. C'est
/// l'usage au Maghreb et en Afrique de l'Ouest, et surtout les prix, les
/// quantités et les numéros de téléphone circulent sous cette forme sur les
/// étiquettes, les bons de livraison et les téléphones eux-mêmes. Des chiffres
/// indo-arabes rendraient un montant illisible pour qui le recopie sur un
/// carnet.
class ChoixLangue {
  const ChoixLangue._();

  static const supportees = [Locale('fr'), Locale('ar')];

  /// Clé de stockage local. Le choix est propre à l'appareil, pas au compte :
  /// un téléphone partagé entre deux personnes garde la langue de celle qui
  /// s'en sert, et le choix survit à une déconnexion.
  static const _cle = 'yalla.langue';

  static Future<Locale?> lire() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_cle);
      if (code == null) return null;
      return Locale(code);
    } catch (_) {
      // Stockage indisponible : on retombe sur la langue du téléphone.
      return null;
    }
  }

  static Future<void> ecrire(Locale? locale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (locale == null) {
        await prefs.remove(_cle);
      } else {
        await prefs.setString(_cle, locale.languageCode);
      }
    } catch (_) {
      // Le choix ne survivra pas au redémarrage, mais l'application marche.
    }
  }
}

/// La langue choisie. Nulle tant que l'utilisateur n'a rien choisi : Flutter
/// retombe alors sur celle du téléphone, ce qui est le bon défaut.
class LangueNotifier extends StateNotifier<Locale?> {
  LangueNotifier() : super(null) {
    _charger();
  }

  Future<void> _charger() async {
    state = await ChoixLangue.lire();
  }

  Future<void> choisir(Locale? locale) async {
    state = locale;
    await ChoixLangue.ecrire(locale);
  }
}

final langueProvider =
    StateNotifierProvider<LangueNotifier, Locale?>((ref) => LangueNotifier());

/// Le sélecteur, posé dans la barre de chaque écran.
///
/// Il montre la langue VERS LAQUELLE on bascule, pas celle en cours : un
/// boutiquier qui ne lit pas le français doit reconnaître « العربية » du
/// premier coup d'œil, sans avoir à comprendre le libellé autour.
class BoutonLangue extends ConsumerWidget {
  const BoutonLangue({super.key, this.surVert = false});

  /// Sur le canevas de marque, un bouton vert sur vert ne se voit pas. On passe
  /// alors en blanc sur un disque translucide, comme les autres actions de
  /// l'en-tête.
  final bool surVert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choisie = ref.watch(langueProvider);
    final courante = choisie?.languageCode ??
        Localizations.localeOf(context).languageCode;
    final versArabe = courante != 'ar';

    return TextButton(
      onPressed: () => ref
          .read(langueProvider.notifier)
          .choisir(Locale(versArabe ? 'ar' : 'fr')),
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 42),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: surVert ? Colors.white : null,
        backgroundColor:
            surVert ? Colors.white.withValues(alpha: .14) : null,
        shape: const StadiumBorder(),
      ),
      child: Text(
        versArabe ? L.of(context).langueArabe : L.of(context).langueFrancais,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}
