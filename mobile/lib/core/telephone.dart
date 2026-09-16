/// Normalisation du numéro de téléphone.
///
/// ATTENTION : ces deux fonctions doivent reproduire **exactement** le
/// comportement de `normaliser_telephone()` et `email_technique()` définies dans
/// `supabase/migrations/*_auth_supabase.sql`.
///
/// Si les deux divergent, l'utilisateur saisit un numéro valide, l'application
/// construit une adresse qui ne correspond à aucun compte, et la connexion
/// échoue sans que rien n'explique pourquoi. C'est le genre de panne qui coûte
/// une journée à diagnostiquer. Les tests de `test/telephone_test.dart`
/// verrouillent la correspondance.
///
/// Pourquoi une adresse technique plutôt que le numéro directement : Supabase
/// Auth n'accepte un numéro que vérifié par SMS, et chaque SMS coûte de
/// l'argent. Le boutiquier saisit son numéro, l'application le convertit, et
/// aucun courriel n'est jamais envoyé à ces adresses.
library;

/// Ramène un numéro ivoirien à sa forme canonique `225XXXXXXXXXX`,
/// quelle que soit la façon dont il a été saisi.
///
/// ```
/// '07 06 30 30 30'      -> '2250706303030'
/// '+225 07 06 30 30 30' -> '2250706303030'
/// '002250706303030'     -> '2250706303030'
/// ```
String normaliserTelephone(String telephone) {
  // On ne garde que les chiffres.
  var v = telephone.replaceAll(RegExp(r'[^0-9]'), '');

  // Préfixe international sous forme 00225 : on le ramène à 225.
  if (v.startsWith('00225')) {
    v = v.substring(2);
  }

  // Numéro national à 10 chiffres commençant par 0 : on préfixe l'indicatif.
  if (v.length == 10 && v.startsWith('0')) {
    v = '225$v';
  }

  return v;
}

/// L'identifiant réellement transmis à Supabase Auth.
String emailTechnique(String telephone) => '${normaliserTelephone(telephone)}@yalla.ci';

/// Un numéro ivoirien canonique fait 13 chiffres : `225` puis 10 chiffres.
/// Contrôle volontairement permissif : il rejette les saisies manifestement
/// incomplètes sans présumer des préfixes d'opérateurs, qui changent.
bool telephoneValide(String telephone) {
  final v = normaliserTelephone(telephone);
  return v.length == 13 && v.startsWith('225');
}
