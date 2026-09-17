import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase.dart';
import 'telephone.dart';

/// Création de comptes Yalla depuis l'application.
///
/// POURQUOI CE N'EST PAS UN SIMPLE `INSERT`. Créer un compte de connexion exige
/// la clé de service, qui contourne toutes les politiques RLS et ne peut donc
/// jamais entrer dans un APK. L'appel passe par la fonction Edge `creer-compte`,
/// qui garde cette clé côté serveur et n'en fait qu'un usage : créer, et
/// supprimer en cas d'échec. La ligne métier, elle, est écrite sous l'identité
/// de l'appelant, si bien que le contrôle de périmètre reste en SQL.
///
/// Conséquence pratique : un distributeur ne peut créer qu'un livreur de sa
/// propre flotte, et un agent recenseur ne peut pas se fabriquer un compte
/// administrateur. Ce fichier ne peut rien y changer.
class ServiceComptes {
  const ServiceComptes();

  /// Mot de passe lisible à voix haute, sur le pas d'une porte.
  ///
  /// Ni `l` ni `1`, ni `O` ni `0` : le compte est dicté au gérant qui le note
  /// sur un carnet, et ces quatre caractères se confondent à l'oral comme à
  /// l'écrit. Un mot de passe mal recopié, c'est un déplacement pour rien.
  static String motDePasseLisible() {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final hasard = Random.secure();
    return List.generate(8, (_) => alphabet[hasard.nextInt(alphabet.length)]).join();
  }

  Future<CompteCree> creer({
    required String nom,
    required String telephone,
    required String role,
    required String motDePasse,
    Map<String, dynamic> details = const {},
  }) async {
    if (!telephoneValide(telephone)) {
      throw const FormatException('Numéro incomplet. Exemple : 07 06 30 30 30');
    }

    final reponse = await supabase.functions.invoke(
      'creer-compte',
      body: {
        'nom': nom.trim(),
        'telephone': telephone,
        'role': role,
        'mot_de_passe': motDePasse,
        'details': details,
      },
    );

    final corps = reponse.data;
    if (reponse.status >= 400) {
      // La fonction Edge renvoie un message déjà rédigé en français, venu soit
      // de ses propres contrôles, soit de l'exception SQL. C'est celui-là qu'il
      // faut montrer, pas un code HTTP.
      final message = corps is Map ? corps['erreur']?.toString() : null;
      throw ErreurCreationCompte(message ?? 'Création du compte impossible');
    }

    final donnees = Map<String, dynamic>.from(corps as Map);
    return CompteCree(
      utilisateurId: donnees['utilisateur_id'] as String?,
      idMetier: donnees['id_metier'] as String?,
      telephone: donnees['telephone'] as String? ?? normaliserTelephone(telephone),
      motDePasse: motDePasse,
      role: role,
    );
  }
}

/// Le compte tel qu'il doit être remis à son titulaire.
class CompteCree {
  const CompteCree({
    required this.telephone,
    required this.motDePasse,
    required this.role,
    this.utilisateurId,
    this.idMetier,
  });

  final String? utilisateurId;
  final String? idMetier;
  final String telephone;
  final String motDePasse;
  final String role;
}

class ErreurCreationCompte implements Exception {
  const ErreurCreationCompte(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Traduit l'échec d'un appel de fonction Edge, qui n'est pas une
/// `PostgrestException` et échappe donc à `messageErreur`.
String messageCompte(Object erreur) {
  if (erreur is ErreurCreationCompte) return erreur.message;
  if (erreur is FormatException) return erreur.message;
  if (erreur is FunctionException) {
    final details = erreur.details;
    if (details is Map && details['erreur'] != null) return details['erreur'].toString();
    return 'Le service de création de comptes est injoignable.';
  }
  return 'Création impossible. Vérifiez votre réseau, puis réessayez.';
}
