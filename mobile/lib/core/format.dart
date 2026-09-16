/// Mise en forme et traduction des erreurs, partagées par les trois écrans.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Durée en français, courte : « 1 h 44 », « 12 min », « 45 s ».
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
/// `18000` devient `18 000 F`.
String montant(num? valeur) {
  if (valeur == null) return '0 F';
  final entier = valeur.round().toString();
  final tampon = StringBuffer();
  for (var i = 0; i < entier.length; i++) {
    if (i > 0 && (entier.length - i) % 3 == 0) tampon.write(' ');
    tampon.write(entier[i]);
  }
  return '$tampon F';
}

/// Traduit une erreur technique en phrase utile.
///
/// Les fonctions métier de la base lèvent des exceptions avec un code SQLSTATE
/// choisi et un message déjà rédigé en français. On les remonte telles quelles :
/// « Cette course vient d'être prise par un autre livreur » est exactement ce
/// que le livreur doit lire. Tout le reste est traduit, car un message brut de
/// PostgREST n'apprend rien à un boutiquier d'Abidjan.
String messageErreur(Object erreur) {
  if (erreur is PostgrestException) {
    final m = erreur.message;

    // Messages levés par nos propres fonctions : déjà écrits pour l'utilisateur.
    if (m.contains('course') || m.contains('rupture') || m.contains('livraison') ||
        m.contains('livreur') || m.contains('flotte') || m.contains('vente')) {
      return m;
    }

    switch (erreur.code) {
      case '42501': // insufficient_privilege
        return 'Vous n\'avez pas les droits pour cette action.';
      case 'PGRST301':
        return 'Session expirée. Reconnectez-vous.';
      default:
        return 'L\'opération a échoué. Réessayez.';
    }
  }
  return 'Connexion impossible. Vérifiez votre réseau.';
}
