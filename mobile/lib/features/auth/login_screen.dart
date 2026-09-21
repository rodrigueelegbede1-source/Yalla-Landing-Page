import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/coque.dart';
import '../../core/langue.dart';
import '../../core/theme.dart';
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

    // L'ÉCRAN D'ACCUEIL DE LA RÉFÉRENCE, adapté. Chez elle : un vert plein, une
    // illustration au trait, un mot de bienvenue, un seul bouton. Ici le vert
    // porte la marque et l'accroche, la feuille blanche porte le formulaire.
    //
    // La différence tient au métier. La référence accueille un promeneur qui a
    // le temps ; celle-ci accueille quelqu'un qui ouvre l'application pour la
    // première fois avec un mot de passe dicté au téléphone, souvent dehors.
    // Le formulaire est donc posé tout de suite, en grand, sur fond clair.
    return Scaffold(
      backgroundColor: Jetons.vert800,
      body: CoqueVerte(
        entete: Padding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MarqueYalla(),
              const SizedBox(height: 26),
              Text(
                l.appNom,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                  color: Jetons.blanc,
                  height: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l.appAccroche,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: .82),
                ),
              ),
            ],
          ),
        ),
        enfant: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 32),
          child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Jetons.alerte.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(Jetons.rChamp),
                        border: Border.all(color: Jetons.alerte.withValues(alpha: .34)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline, size: 20, color: Jetons.alerte),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_erreur!,
                                style: const TextStyle(fontSize: 14, height: 1.4)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 26),
                  FilledButton(
                    onPressed: _enCours ? null : _connecter,
                    child: _enCours
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Jetons.blanc),
                          )
                        : Text(l.seConnecter),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    l.indiceConnexion,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Jetons.encre.withValues(alpha: .58),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Center(child: BoutonLangue()),
                ],
              ),
            ),
        ),
      ),
    );
  }
}

/// La marque, au trait blanc, dans le canevas vert.
///
/// Reprend exactement le motif du logo du site : la barre du Y, le carton
/// incliné, la roue. Dessiné plutôt qu'importé, pour la même raison que la
/// bande de marché : net à toutes les densités, et zéro octet dans l'APK.
class MarqueYalla extends StatelessWidget {
  const MarqueYalla({super.key, this.taille = 44});

  final double taille;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: taille,
        height: taille,
        child: CustomPaint(painter: _PeintreMarque()),
      );
}

class _PeintreMarque extends CustomPainter {
  @override
  void paint(Canvas toile, Size t) {
    final e = t.width / 40; // Le motif est dessiné sur une grille de 40.

    final trait = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2 * e
      ..strokeCap = StrokeCap.round
      ..color = Jetons.jaune;

    final plein = Paint()..color = Jetons.jaune;

    // La barre du Y.
    toile.drawPath(
      Path()
        ..moveTo(9 * e, 10 * e)
        ..lineTo(15.2 * e, 10 * e)
        ..lineTo(24.7 * e, 29.5 * e),
      trait,
    );

    // Le carton, incliné comme sur le logo.
    toile.save();
    toile.translate(27 * e, 13 * e);
    toile.rotate(-19 * 3.14159 / 180);
    toile.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 13 * e, height: 13 * e),
        Radius.circular(1.6 * e),
      ),
      plein,
    );
    toile.restore();

    // La roue.
    toile.drawCircle(Offset(17.5 * e, 31.5 * e), 4.2 * e, plein);
  }

  @override
  bool shouldRepaint(covariant CustomPainter ancien) => false;
}
