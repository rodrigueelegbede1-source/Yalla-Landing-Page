import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _telephoneCtrl = TextEditingController();
  final _motDePasseCtrl = TextEditingController();
  bool _enCours = false;
  String? _erreur;

  Future<void> _seConnecter() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await ref.read(sessionProvider.notifier).connecter(_telephoneCtrl.text.trim(), _motDePasseCtrl.text);
    } catch (_) {
      setState(() => _erreur = 'Numéro ou mot de passe incorrect.');
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Yalla', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Connexion à votre espace'),
              const SizedBox(height: 32),
              TextField(
                controller: _telephoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Téléphone', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _motDePasseCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Mot de passe', border: OutlineInputBorder()),
              ),
              if (_erreur != null) ...[
                const SizedBox(height: 12),
                Text(_erreur!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _enCours ? null : _seConnecter,
                child: _enCours
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Se connecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
