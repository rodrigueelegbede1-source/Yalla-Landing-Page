/// Le système visuel de Yalla.
///
/// ════════════════════════════════════════════════════════════════════════════
/// CE QU'ON REPREND À LA RÉFÉRENCE, ET CE QU'ON LUI REFUSE
/// ════════════════════════════════════════════════════════════════════════════
///
/// La référence est une application de tourisme : un vert plein en canevas, une
/// feuille blanche à grand rayon qui le chevauche, une grille de tuiles d'accès
/// rapide, des cartes douces, un trait blanc illustratif. C'est une très bonne
/// grammaire, et on la reprend presque entièrement.
///
/// ON LUI REFUSE SON TEMPO. Une application de randonnée se feuillette assis,
/// à l'ombre, sur un téléphone récent. Yalla se tient d'une main derrière un
/// comptoir, en plein soleil d'Abidjan, sur un écran d'entrée de gamme, par
/// quelqu'un qu'un client interrompt. Trois conséquences, appliquées partout :
///
///   * LE TEXTE MONTE. La référence descend à 11 et 12 points pour aérer ; ici
///     rien d'utile ne passe sous 13, et les chiffres qui décident sont gros.
///   * LE CONTRASTE MONTE. Les gris à 40 % de la référence disparaissent au
///     soleil. Le texte secondaire ne descend pas sous 55 % d'opacité.
///   * LE DÉCOR NE CROISE JAMAIS LE TEXTE. Le trait blanc illustratif reste une
///     bande, jamais un fond : un filet d'un pixel derrière un mot le rend
///     illisible sur une dalle bon marché.
///
/// ════════════════════════════════════════════════════════════════════════════
/// CE QUE LA RÉFÉRENCE N'A PAS, ET QUE YALLA GARDE
/// ════════════════════════════════════════════════════════════════════════════
///
/// Le jaune signalétique du logo. La référence n'a aucun accent : tout y est
/// vert ou blanc, ce qui va pour un objet qu'on parcourt, pas pour un objet qui
/// alerte. Le jaune est donc réservé à UNE SEULE CHOSE par écran, celle qui
/// attend un geste. Employé deux fois, il ne veut plus rien dire.
///
/// ════════════════════════════════════════════════════════════════════════════
/// PAS DE POLICE EMBARQUÉE, ET C'EST UN ARBITRAGE
/// ════════════════════════════════════════════════════════════════════════════
///
/// Le site utilise Sora et Inter. Les embarquer coûterait environ deux cents
/// kilo-octets par graisse dans un APK qui pèse déjà trente-quatre méga-octets
/// et se télécharge hors Play Store, souvent en données mobiles payées au
/// mégaoctet. La police système rend la même chose à cette taille d'écran. Ce
/// sont donc l'échelle, les graisses et l'interlettrage qui portent l'identité,
/// pas le dessin des lettres.
///
/// ════════════════════════════════════════════════════════════════════════════
/// TOUT EST DIRECTIONNEL
/// ════════════════════════════════════════════════════════════════════════════
///
/// L'arabe bascule l'interface en droite-à-gauche. Aucun rayon, aucune marge et
/// aucun alignement de ce fichier n'emploie `left` ou `right` : uniquement
/// `start`, `end` et leurs équivalents. Un seul `EdgeInsets.only(left:)` oublié
/// et la moitié des boutiquiers voit une interface de travers.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Les jetons. Repris du site, à l'identique : un produit qui change de couleur
/// entre son site et son application n'a pas d'identité, il a deux identités.
abstract final class Jetons {
  static const vert950 = Color(0xFF062718);
  static const vert900 = Color(0xFF0A3D24);
  static const vert800 = Color(0xFF0E4A2C);
  static const vert700 = Color(0xFF146B3A);
  static const vert600 = Color(0xFF1A7D45);
  static const vert500 = Color(0xFF229453);

  /// Le jaune du logo. UNE seule chose par écran, celle qui attend un geste.
  static const jaune = Color(0xFFFFE500);

  static const creme = Color(0xFFF6F4EC);
  static const creme2 = Color(0xFFEDEAE0);
  static const encre = Color(0xFF08160E);
  static const blanc = Color(0xFFFFFFFF);

  static const alerte = Color(0xFFFF5C39);
  static const ok = Color(0xFF3ED598);

  /// Les rayons. La feuille est la plus arrondie parce que c'est elle qui donne
  /// le caractère ; tout ce qui vit dedans l'est moins, sans quoi l'écran
  /// devient une bouillie de coins ronds.
  static const rFeuille = 30.0;
  static const rCarte = 20.0;
  static const rTuile = 18.0;
  static const rChamp = 14.0;

  /// L'ombre des cartes. Très basse et très large : une ombre marquée ferait
  /// flotter chaque carte, et douze cartes qui flottent ne hiérarchisent plus
  /// rien. Celle-ci décolle à peine, juste assez pour séparer du crème.
  static List<BoxShadow> get ombreCarte => const [
        BoxShadow(color: Color(0x0F062718), blurRadius: 18, offset: Offset(0, 6)),
      ];

  /// L'ombre de la feuille, qui doit se lire par-dessus le vert.
  static List<BoxShadow> get ombreFeuille => const [
        BoxShadow(color: Color(0x26062718), blurRadius: 28, offset: Offset(0, -6)),
      ];

  /// La hauteur minimale d'une cible tactile. Quarante-huit points est le
  /// minimum d'Android ; on monte à cinquante-six pour ce qui se touche en
  /// marchant ou avec des mains occupées.
  static const cible = 56.0;
}

/// Le thème clair, et le seul. Pas de thème sombre : la moitié de l'usage se
/// fait dehors, en plein jour, où un fond noir se transforme en miroir. Un
/// thème sombre mal éprouvé coûterait plus qu'il ne rapporte.
ThemeData themeYalla() {
  const couleurs = ColorScheme.light(
    primary: Jetons.vert700,
    onPrimary: Jetons.blanc,
    primaryContainer: Jetons.vert900,
    onPrimaryContainer: Jetons.blanc,
    secondary: Jetons.vert500,
    onSecondary: Jetons.blanc,
    tertiary: Jetons.jaune,
    onTertiary: Jetons.vert950,
    surface: Jetons.blanc,
    onSurface: Jetons.encre,
    surfaceContainerLowest: Jetons.blanc,
    surfaceContainer: Jetons.creme,
    surfaceContainerHigh: Jetons.creme2,
    onSurfaceVariant: Color(0x9908160E),
    outline: Color(0x6608160E),
    outlineVariant: Color(0x2608160E),
    error: Jetons.alerte,
    onError: Jetons.blanc,
  );

  final base = ThemeData(colorScheme: couleurs, useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: Jetons.creme,
    splashFactory: InkSparkle.splashFactory,

    // La barre d'état en clair sur le vert : le canevas monte jusqu'en haut de
    // l'écran, et des icônes système sombres y deviendraient invisibles.
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Jetons.blanc,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      titleTextStyle: TextStyle(
        color: Jetons.blanc,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),

    textTheme: base.textTheme.copyWith(
      // Le chiffre qui décide. Gros, serré, tabulaire : un montant qui bouge
      // d'un pixel à chaque franc est illisible au coup d'œil.
      displaySmall: const TextStyle(
        fontSize: 34, fontWeight: FontWeight.w700, height: 1.05,
        letterSpacing: -0.8, color: Jetons.encre,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      titleLarge: const TextStyle(
        fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4,
        color: Jetons.vert900,
      ),
      titleMedium: const TextStyle(
        fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2,
        color: Jetons.vert900,
      ),
      // Rien d'utile ne descend sous 13. La référence va jusqu'à 11 pour aérer ;
      // au soleil, 11 points ne se lit pas.
      bodyLarge: const TextStyle(fontSize: 15.5, height: 1.45, color: Jetons.encre),
      bodyMedium: const TextStyle(fontSize: 14, height: 1.45, color: Jetons.encre),
      bodySmall: TextStyle(fontSize: 13, height: 1.4, color: Jetons.encre.withValues(alpha: .62)),
      labelLarge: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0),
    ),

    cardTheme: CardThemeData(
      color: Jetons.blanc,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Jetons.rCarte),
      ),
    ),

    // Des pilules, comme la référence. Un bouton rectangulaire à coins
    // légèrement arrondis se confond avec un champ de saisie ; une pilule, non.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(Jetons.cible),
        backgroundColor: Jetons.vert700,
        foregroundColor: Jetons.blanc,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: Jetons.vert700,
        side: const BorderSide(color: Color(0x5C146B3A), width: 1.4),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Jetons.vert700,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Jetons.blanc,
      contentPadding: const EdgeInsetsDirectional.fromSTEB(18, 18, 18, 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Jetons.rChamp),
        borderSide: const BorderSide(color: Color(0x2608160E), width: 1.4),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Jetons.rChamp),
        borderSide: const BorderSide(color: Color(0x2608160E), width: 1.4),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Jetons.rChamp),
        borderSide: const BorderSide(color: Jetons.vert700, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Jetons.rChamp),
        borderSide: const BorderSide(color: Jetons.alerte, width: 1.4),
      ),
      labelStyle: TextStyle(color: Jetons.encre.withValues(alpha: .62), fontSize: 14.5),
      floatingLabelStyle: const TextStyle(color: Jetons.vert700, fontWeight: FontWeight.w600),
    ),

    // La barre du bas est blanche et posée sur le crème : un fond vert en bas
    // ET en haut enfermerait l'écran dans un cadre, et le contenu n'aurait plus
    // sa place à lui.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Jetons.blanc,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Jetons.vert700.withValues(alpha: .12),
      elevation: 0,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (etats) => TextStyle(
          fontSize: 11.5,
          fontWeight: etats.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: etats.contains(WidgetState.selected)
              ? Jetons.vert800
              : Jetons.encre.withValues(alpha: .55),
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (etats) => IconThemeData(
          size: 24,
          color: etats.contains(WidgetState.selected)
              ? Jetons.vert800
              : Jetons.encre.withValues(alpha: .55),
        ),
      ),
    ),

    // Le compteur de non-lus. Jaune sur vert foncé : c'est le seul endroit où
    // le jaune apparaît par défaut, et il ne doit apparaître nulle part
    // ailleurs sans raison.
    badgeTheme: const BadgeThemeData(
      backgroundColor: Jetons.alerte,
      textColor: Jetons.blanc,
      textStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Jetons.vert900,
      contentTextStyle: const TextStyle(color: Jetons.blanc, fontSize: 14.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Jetons.rChamp)),
      insetPadding: const EdgeInsets.all(16),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: Jetons.blanc,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Jetons.rCarte)),
      titleTextStyle: const TextStyle(
        fontSize: 19, fontWeight: FontWeight.w700, color: Jetons.vert900),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Jetons.blanc,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Jetons.rFeuille)),
      ),
    ),

    chipTheme: const ChipThemeData(
      backgroundColor: Jetons.creme2,
      side: BorderSide.none,
      shape: StadiumBorder(),
      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    ),

    dividerTheme: const DividerThemeData(
      color: Color(0x1A08160E), thickness: 1, space: 1),

    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Jetons.vert700),
  );
}
