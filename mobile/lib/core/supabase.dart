import 'package:supabase_flutter/supabase_flutter.dart';

/// Connexion à Supabase.
///
/// Les deux valeurs se passent à la compilation, jamais en dur dans le code :
///
/// ```
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJhbGci...
/// ```
///
/// La clé « anon » est publique par conception : elle est lisible dans
/// n'importe quel APK décompilé, et c'est normal. Ce n'est pas elle qui protège
/// les données, ce sont les politiques RLS. Toute la sécurité du produit repose
/// sur `supabase/migrations/*_rls_perimetres.sql`, et sur rien d'autre.
///
/// La clé de service, elle, ne doit JAMAIS entrer dans cette application :
/// elle contourne RLS et donnerait à n'importe quel porteur d'APK l'accès à
/// l'intégralité du réseau.
class ConfigSupabase {
  const ConfigSupabase._();

  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get estRenseignee => url.isNotEmpty && anonKey.isNotEmpty;
}

/// À appeler une fois au démarrage, avant `runApp`.
Future<void> initialiserSupabase() async {
  if (!ConfigSupabase.estRenseignee) {
    throw StateError(
      'SUPABASE_URL et SUPABASE_ANON_KEY sont vides. Relancez avec :\n'
      '  flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
    );
  }

  await Supabase.initialize(
    url: ConfigSupabase.url,
    publishableKey: ConfigSupabase.anonKey,
    authOptions: const FlutterAuthClientOptions(
      // Le jeton est conservé et rafraîchi par le client. Un livreur qui roule
      // toute la journée ne doit pas se retrouver déconnecté au bout d'une heure.
      autoRefreshToken: true,
    ),
  );
}

/// Raccourci vers le client, une fois initialisé.
SupabaseClient get supabase => Supabase.instance.client;
