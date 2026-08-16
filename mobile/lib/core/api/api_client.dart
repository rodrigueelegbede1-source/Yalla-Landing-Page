import 'package:dio/dio.dart';
import '../storage/token_storage.dart';

/// Point d'entrée unique vers l'API NestJS (voir yalla-backend-api).
/// En développement, remplacer par l'IP de la machine qui fait tourner
/// l'API (localhost ne fonctionne pas depuis un émulateur/téléphone physique).
const String apiBaseUrl = String.fromEnvironment(
  'YALLA_API_URL',
  defaultValue: 'http://10.0.2.2:3000',
);

class ApiClient {
  ApiClient(this._tokenStorage) {
    dio = Dio(BaseOptions(baseUrl: apiBaseUrl, connectTimeout: const Duration(seconds: 10)));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokenStorage.lireToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final TokenStorage _tokenStorage;
  late final Dio dio;
}
