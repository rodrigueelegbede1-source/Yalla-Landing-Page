import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase.dart';
import '../telephone.dart';

/// Identité de l'utilisateur connecté, telle que la porte le jeton.
///
/// `role` et `idMetier` ne viennent pas d'un appel réseau mais des claims
/// injectés dans le jeton par le hook `custom_access_token_hook` (voir
/// `supabase/migrations/*_auth_supabase.sql`). Ils sont donc disponibles
/// immédiatement, sans requête, et ils sont signés : l'application ne peut pas
/// se mentir à elle-même sur son propre rôle.
class SessionYalla {
  const SessionYalla({
    this.role,
    this.nom,
    this.idMetier,
    this.utilisateurId,
    this.enCoursDeChargement = false,
  });

  const SessionYalla.chargement() : this(enCoursDeChargement: true);
  const SessionYalla.deconnecte() : this();

  final String? role;
  final String? nom;

  /// Identifiant dans la table du rôle : `points_de_vente.id`,
  /// `distributeurs.id` ou `livreurs.id`. Nul pour un administrateur.
  final String? idMetier;

  final String? utilisateurId;
  final bool enCoursDeChargement;

  bool get estConnecte => role != null;

  /// Un compte authentifié mais sans ligne de rôle rattachée. Cela arrive quand
  /// un compte Supabase a été créé sans passer par `rattacher_compte_auth()`.
  /// L'application ne peut rien afficher d'utile dans cet état, et doit le dire
  /// plutôt que de montrer un écran vide.
  bool get rattachementIncomplet => estConnecte && idMetier == null && role != 'administrateur';
}

/// Lit les claims d'un jeton JWT sans vérifier sa signature.
///
/// L'absence de vérification est volontaire et sans risque ici : le jeton vient
/// du client Supabase, qui l'a obtenu du serveur, et il n'est utilisé que pour
/// afficher la bonne interface. Les décisions qui comptent sont prises côté
/// base, par les politiques RLS, qui vérifient la signature elles-mêmes.
Map<String, dynamic> _claimsDuJeton(String jeton) {
  final parties = jeton.split('.');
  if (parties.length != 3) return const {};
  try {
    final charge = parties[1];
    final normalise = base64Url.normalize(charge);
    return jsonDecode(utf8.decode(base64Url.decode(normalise))) as Map<String, dynamic>;
  } catch (_) {
    // Un jeton illisible équivaut à pas de session : on ne devine pas.
    return const {};
  }
}

SessionYalla _sessionDepuis(Session? session) {
  if (session == null) return const SessionYalla.deconnecte();

  final claims = _claimsDuJeton(session.accessToken);
  final role = claims['user_role'] as String?;
  if (role == null) {
    // Authentifié côté Supabase, mais le hook n'a rien trouvé dans
    // `utilisateurs`. Le compte existe sans profil métier.
    return const SessionYalla(role: null);
  }

  return SessionYalla(
    role: role,
    nom: claims['nom'] as String?,
    idMetier: claims['id_metier'] as String?,
    utilisateurId: claims['utilisateur_id'] as String?,
  );
}

/// La session, tenue à jour en continu.
///
/// On s'abonne au flux d'état de Supabase plutôt que de lire la session une
/// fois au démarrage : un rafraîchissement de jeton, une déconnexion depuis un
/// autre appareil ou une expiration se répercutent alors tout seuls sur
/// l'interface. L'ancienne version lisait le rôle une fois sur le disque et
/// considérait l'utilisateur connecté même avec un jeton expiré.
final sessionProvider = StreamProvider<SessionYalla>((ref) async* {
  yield _sessionDepuis(supabase.auth.currentSession);

  await for (final etat in supabase.auth.onAuthStateChange) {
    yield _sessionDepuis(etat.session);
  }
});

/// Actions d'authentification.
final authProvider = Provider((ref) => const ServiceAuth());

class ServiceAuth {
  const ServiceAuth();

  /// Connexion par numéro de téléphone.
  ///
  /// Le numéro est converti en adresse technique, exactement comme le fait la
  /// base. Voir `lib/core/telephone.dart` pour le pourquoi.
  Future<void> connecter({required String telephone, required String motDePasse}) async {
    if (!telephoneValide(telephone)) {
      throw const FormatException('Numéro incomplet. Exemple : 07 06 30 30 30');
    }
    await supabase.auth.signInWithPassword(
      email: emailTechnique(telephone),
      password: motDePasse,
    );
  }

  Future<void> deconnecter() => supabase.auth.signOut();
}
