import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  final _storage = const FlutterSecureStorage();

  static const _cleToken = 'yalla_access_token';
  static const _cleRole = 'yalla_role';
  static const _cleNom = 'yalla_nom';
  static const _cleIdMetier = 'yalla_id_metier';

  Future<void> enregistrer({
    required String token,
    required String role,
    required String nom,
    String? idMetier,
  }) async {
    await _storage.write(key: _cleToken, value: token);
    await _storage.write(key: _cleRole, value: role);
    await _storage.write(key: _cleNom, value: nom);
    if (idMetier != null) {
      await _storage.write(key: _cleIdMetier, value: idMetier);
    }
  }

  Future<String?> lireToken() => _storage.read(key: _cleToken);
  Future<String?> lireRole() => _storage.read(key: _cleRole);
  Future<String?> lireNom() => _storage.read(key: _cleNom);
  Future<String?> lireIdMetier() => _storage.read(key: _cleIdMetier);

  Future<void> effacer() async {
    await _storage.deleteAll();
  }
}
