import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/langue.dart';
import '../../l10n/app_localizations.dart';

/// Connexion par numéro de téléphone.
///
/// Le numéro plutôt que l'adresse email : sur le marché visé, un gérant de
/// boutique ou un livreur a toujours un numéro, rarement un email actif.
/// La conversion en identifiant Supabase se fait dans `core/telephone.dart`.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _telephone = TextEditingController();
  final _motDePasse = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _enCours = false;
  bool _motDePasseVisible = false;
  String? _erreur;

  @override
  void dispose() {
    _telephone.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  Future<void> _connecter() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      await ref.read(authProvider).connecter(
            telephone: _telephone.text,
            motDePasse: _motDePasse.text,
          );
      // Pas de navigation ici : `sessionProvider` écoute l'état Supabase et
      // l'écran racine bascule tout seul. Naviguer à la main créerait deux
      // sources de vérité sur « suis-je connecté ».
    } on AuthException catch (e) {
      // On ne répète pas le message de Supabase, qui parle d'email alors que
      // l'utilisateur a saisi un numéro. Cela ne ferait que le dérouter.
      if (!mounted) return;
      final l = L.of(context);
      setState(() => _erreur = e.statusCode == '400'
          ? l.erreurIdentifiants
          : l.erreurReseau);
    } on FormatException catch (e) {
      setState(() => _erreur = e.message);
    } catch (_) {
      if (!mounted) return;
      final l = L.of(context);
      setState(() => _erreur = l.erreurReseau);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l.appNom,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          )),
                  const SizedBox(height: 8),
                  Text(l.appAccroche,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 40),
                  TextFormField(
                    controller: _telephone,
                    keyboardType: TextInputType.phone,
                    // Un numéro se lit de gauche à droite même en arabe : sans cette
                    // direction imposée, le RTL inverse l'ordre des groupes de
                    // chiffres et l'exemple s'affiche à l'envers.
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                    ],
                    decoration: InputDecoration(
                      labelText: l.numeroTelephone,
                      hintText: '07 06 30 30 30',
                      prefixIcon: const Icon(Icons.phone_outlined),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? l.numeroTelephone : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _motDePasse,
                    obscureText: !_motDePasseVisible,
                    decoration: InputDecoration(
                      labelText: l.motDePasse,
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_motDePasseVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        tooltip: l.motDePasse,
                        onPressed: () =>
                            setState(() => _motDePasseVisible = !_motDePasseVisible),
                      ),
                    ),
                    onFieldSubmitted: (_) => _connecter(),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? l.motDePasse : null,
                  ),
                  if (_erreur != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_erreur!)),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _enCours ? null : _connecter,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _enCours
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l.seConnecter),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l.indiceConnexion,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  const Center(child: BoutonLangue()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
