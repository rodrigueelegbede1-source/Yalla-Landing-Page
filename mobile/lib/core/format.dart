/// Mise en forme et traduction des erreurs, partagées par les écrans.
library;

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';

/// Durée courte : « 1 h 44 », « 12 min », « 45 s ».
///
/// Volontairement non traduite. Les abréviations d'unités de temps sont les
/// mêmes sur les deux versions : en arabe ivoirien comme en français, un
/// boutiquier lit « 12 min » sans hésiter, et une transcription arabe de
/// « min » serait plus longue à lire qu'à comprendre.
String duree(int secondes) {
  if (secondes >= 3600) {
    final h = secondes ~/ 3600;
    final m = (secondes % 3600) ~/ 60;
    return m == 0 ? '$h h' : '$h h $m';
  }
  if (secondes >= 60) return '${secondes ~/ 60} min';
  return '$secondes s';
}

/// Ancienneté d'un signalement, telle qu'affichée dans les maquettes.
String depuis(num? secondes) {
  if (secondes == null) return '';
  return duree(secondes.toInt());
}

/// Montant en francs CFA, avec séparateur de milliers.
///
/// Les chiffres restent en écriture occidentale même en arabe : c'est l'usage
/// en Afrique de l'Ouest, et surtout les prix circulent sous cette forme sur
/// les étiquettes et les bons de livraison. Des chiffres indo-arabes rendraient
/// un montant illisible pour qui le recopie sur un carnet.
String montantBrut(num? valeur) {
  if (valeur == null) return '0';
  final entier = valeur.round().toString();
  final tampon = StringBuffer();
  for (var i = 0; i < entier.length; i++) {
    if (i > 0 && (entier.length - i) % 3 == 0) tampon.write(' ');
    tampon.write(entier[i]);
  }
  return tampon.toString();
}

/// Montant avec son unité, dans la langue courante.
String montant(BuildContext context, num? valeur) =>
    L.of(context).francsCfa(montantBrut(valeur));

/// Traduit une erreur technique en phrase utile.
///
/// Les fonctions métier de la base lèvent des exceptions avec un code SQLSTATE
/// choisi et un message déjà rédigé **en français**. On les remonte telles
/// quelles quand elles portent une information que l'utilisateur doit lire :
/// « Cette course vient d'être prise par un autre livreur » est exactement ce
/// qu'il faut dire.
///
/// LIMITE CONNUE ET ASSUMÉE : ces messages-là ne sont pas traduits en arabe.
/// Les traduire supposerait de renvoyer un code depuis la base plutôt qu'une
/// phrase, ce qui est la bonne solution mais touche toutes les fonctions
/// métier. En attendant, un boutiquier arabophone verra une poignée de messages
/// d'erreur en français, sur des cas de concurrence qui restent rares.
String messageErreur(BuildContext context, Object erreur) {
  final l = L.of(context);

  if (erreur is PostgrestException) {
    final m = erreur.message;

    if (m.contains('course') ||
        m.contains('rupture') ||
        m.contains('livraison') ||
        m.contains('livreur') ||
        m.contains('flotte') ||
        m.contains('boutique') ||
        m.contains('vente')) {
      return m;
    }

    switch (erreur.code) {
      case '42501': // insufficient_privilege
        return l.erreurDroits;
      case 'PGRST301':
        return l.erreurSession;
      default:
        return l.erreurGenerique;
    }
  }
  return l.erreurReseau;
}
