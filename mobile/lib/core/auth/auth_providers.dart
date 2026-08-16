import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../storage/token_storage.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(tokenStorageProvider));
});

class SessionYalla {
  const SessionYalla({this.role, this.nom, this.idMetier, required this.enCoursDeChargement});

  final String? role;
  final String? nom;
  final String? idMetier;
  final bool enCoursDeChargement;

  bool get estConnecte => role != null;

  SessionYalla copyWith({String? role, String? nom, String? idMetier, bool? enCoursDeChargement}) => SessionYalla(
        role: role ?? this.role,
        nom: nom ?? this.nom,
        idMetier: idMetier ?? this.idMetier,
        enCoursDeChargement: enCoursDeChargement ?? this.enCoursDeChargement,
      );
}

class SessionNotifier extends StateNotifier<SessionYalla> {
  SessionNotifier(this._api, this._storage) : super(const SessionYalla(enCoursDeChargement: true)) {
    _restaurerSession();
  }

  final ApiClient _api;
  final TokenStorage _storage;

  Future<void> _restaurerSession() async {
    final role = await _storage.lireRole();
    final nom = await _storage.lireNom();
    final idMetier = await _storage.lireIdMetier();
    state = SessionYalla(role: role, nom: nom, idMetier: idMetier, enCoursDeChargement: false);
  }

  /// Les 5 rôles (`administrateur`, `fabricant`, `livreur`, `point_de_vente`,
  /// `agent_recenseur`) partagent le même endpoint de connexion — l'API renvoie
  /// le rôle et l'ID métier (fabricantId/livreurId/pointDeVenteId/agentRecenseurId)
  /// dans la même réponse, ce qui pilote à la fois le routage et les appels API
  /// suivants sans requête supplémentaire.
  Future<void> connecter(String telephone, String motDePasse) async {
    final reponse = await _api.dio.post('/auth/login', data: {
      'telephone': telephone,
      'motDePasse': motDePasse,
    });

    final token = reponse.data['access_token'] as String;
    final utilisateur = reponse.data['utilisateur'] as Map<String, dynamic>;
    final idMetier = utilisateur['idMetier'] as String?;

    await _storage.enregistrer(
      token: token,
      role: utilisateur['role'],
      nom: utilisateur['nom'],
      idMetier: idMetier,
    );
    state = SessionYalla(role: utilisateur['role'], nom: utilisateur['nom'], idMetier: idMetier, enCoursDeChargement: false);
  }

  Future<void> deconnecter() async {
    await _storage.effacer();
    state = const SessionYalla(enCoursDeChargement: false);
  }
}

final sessionProvider = StateNotifierProvider<SessionNotifier, SessionYalla>((ref) {
  return SessionNotifier(ref.watch(apiClientProvider), ref.watch(tokenStorageProvider));
});
