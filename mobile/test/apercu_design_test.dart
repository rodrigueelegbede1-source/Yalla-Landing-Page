/// Aperçu du système visuel, rendu en image.
///
///   flutter test --update-goldens test/apercu_design_test.dart
///
/// POURQUOI CE FICHIER EXISTE. Une refonte visuelle qu'on n'a pas regardée
/// n'est pas finie : `flutter analyze` dit que le code compile, jamais que
/// l'écran est lisible. Sans émulateur Android sur cette machine, ce test rend
/// les écrans hors écran et écrit des PNG dans `test/apercu/`, qui s'ouvrent
/// comme n'importe quelle image.
///
/// CE N'EST PAS UN TEST DE NON-RÉGRESSION. On ne compare à aucune référence :
/// le rendu d'un texte varie d'une version de Flutter à l'autre, et un test qui
/// échoue parce qu'une lettre a bougé d'un pixel finit par être désactivé. Ces
/// images servent à VOIR, pas à verrouiller.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_mobile/core/coque.dart';
import 'package:yalla_mobile/core/theme.dart';

void main() {
  // Un écran d'entrée de gamme courant à Abidjan : 360 × 800 en points, densité
  // 2. C'est sur celui-là que la lisibilité se joue, pas sur un grand écran.
  const taille = Size(360, 800);

  Widget encadrer(Widget enfant) => MediaQuery(
        data: const MediaQueryData(size: taille, devicePixelRatio: 2),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: themeYalla(),
          home: enfant,
        ),
      );

  testWidgets('aperçu — canevas, feuille et tuiles', (tester) async {
    await tester.binding.setSurfaceSize(taille);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(encadrer(
      Scaffold(
        backgroundColor: Jetons.vert800,
        body: CoqueVerte(
          entete: SalutationCanevas(
            salutation: 'Bonjour,',
            nom: 'Superette Akwaba',
            detail: '3 ruptures à confirmer · 1 message',
            actions: [
              BoutonCanevas(icone: Icons.bolt, onTap: () {}),
              BoutonCanevas(icone: Icons.logout, onTap: () {}),
            ],
          ),
          enfant: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              const TitreBloc('Que faites-vous ?'),
              GrilleActions(tuiles: [
                TuileAction(
                    icone: Icons.point_of_sale,
                    libelle: 'Encaisser',
                    onTap: () {}),
                TuileAction(
                    icone: Icons.menu_book,
                    libelle: 'Catalogue',
                    teinte: Jetons.vert500,
                    onTap: () {}),
                TuileAction(
                    icone: Icons.inventory_2,
                    libelle: 'Stock',
                    teinte: const Color(0xFF7A5CC4),
                    onTap: () {}),
                TuileAction(
                    icone: Icons.check_circle,
                    libelle: 'À confirmer',
                    compteur: 3,
                    teinte: Jetons.alerte,
                    onTap: () {}),
                TuileAction(
                    icone: Icons.mail,
                    libelle: 'Messages',
                    compteur: 1,
                    teinte: const Color(0xFF2E8BC0),
                    onTap: () {}),
                TuileAction(
                    icone: Icons.help_outline,
                    libelle: 'Aide',
                    teinte: const Color(0xFF8A7A2E),
                    onTap: () {}),
              ]),
              const SizedBox(height: 22),
              const TitreBloc('À confirmer', action: 'Tout voir'),
              CarteDouce(
                accent: Jetons.alerte,
                enfant: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Riz parfumé La Rizière 900g',
                        style: TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('Votre caisse l’a vu tomber à zéro il y a 12 min',
                        style: TextStyle(
                            fontSize: 13,
                            color: Jetons.encre.withValues(alpha: .62))),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                          child: OutlinedButton(
                              onPressed: () {}, child: const Text('Non'))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: FilledButton(
                              onPressed: () {},
                              child: const Text('Confirmer'))),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              CarteDouce(
                enfant: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Jetons.vert700.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.campaign_outlined,
                        color: Jetons.vert700),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Maintenance samedi',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        SizedBox(height: 3),
                        Text('Le réseau sera indisponible de 6 h à 8 h.',
                            style: TextStyle(fontSize: 13.5)),
                      ],
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: 0,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.point_of_sale_outlined), label: 'Caisse'),
            NavigationDestination(
                icon: Icon(Icons.menu_book_outlined), label: 'Catalogue'),
            NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined), label: 'Stock'),
            NavigationDestination(
                icon: Icon(Icons.mail_outline), label: 'Messages'),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('apercu/boutiquier.png'),
    );
  });

  // LE CAS QUI A CASSÉ EN PRODUCTION, gardé en aperçu.
  //
  // Un `FilledButton` en `trailing` d'un `ListTile` : le thème lui imposait une
  // largeur minimale infinie via `Size.fromHeight`, le bouton réclamait toute
  // la ligne, et le titre du produit se retrouvait à zéro de large. Il
  // s'écrivait alors une lettre par ligne, à la verticale, sans qu'aucune
  // erreur ne soit levée ni qu'un test n'échoue.
  //
  // Deux listes du produit avaient le même montage, le catalogue du boutiquier
  // et les courses du livreur. L'image ci-dessous les couvre toutes les deux.
  testWidgets('aperçu — liste avec bouton en bout de ligne', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(encadrer(
      Scaffold(
        backgroundColor: Jetons.creme,
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final cas in [
              ('Tomate concentrée Alyssa sachet 56g', 'Demander'),
              ('Riz parfumé Vietnam La Rizière 900g', 'Prendre'),
              ('Eau', 'Demander'),
            ])
              Card(
                margin: const EdgeInsetsDirectional.only(bottom: 8),
                child: ListTile(
                  contentPadding:
                      const EdgeInsetsDirectional.fromSTEB(12, 6, 8, 6),
                  leading: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Jetons.vert700.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  title: Text(cas.$1, style: const TextStyle(fontSize: 14)),
                  subtitle: const Text('SDTM-CI (Carré d’Or)',
                      style: TextStyle(fontSize: 11.5)),
                  trailing: FilledButton.tonal(
                      onPressed: () {},
                      style: boutonBoutDeLigne,
                      child: Text(cas.$2)),
                ),
              ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('apercu/liste_bouton.png'),
    );
  });

  testWidgets('aperçu — connexion', (tester) async {
    await tester.binding.setSurfaceSize(taille);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(encadrer(
      Scaffold(
        backgroundColor: Jetons.vert800,
        body: CoqueVerte(
          entete: const Padding(
            padding: EdgeInsets.fromLTRB(28, 18, 28, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarqueApercu(),
                SizedBox(height: 26),
                Text('Yalla',
                    style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.2,
                        color: Jetons.blanc,
                        height: 1)),
                SizedBox(height: 8),
                Text('La rupture de stock, réglée en temps réel',
                    style: TextStyle(
                        fontSize: 15, height: 1.4, color: Color(0xD1FFFFFF))),
                SizedBox(height: 26),
              ],
            ),
          ),
          enfant: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const TextField(
                  decoration: InputDecoration(
                    labelText: 'Numéro de téléphone',
                    hintText: '07 06 30 30 30',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                const TextField(
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon: Icon(Icons.lock_outline),
                    suffixIcon: Icon(Icons.visibility_outlined),
                  ),
                ),
                const SizedBox(height: 26),
                FilledButton(
                    onPressed: () {}, child: const Text('Se connecter')),
                const SizedBox(height: 22),
                Text(
                  'Votre compte vous est remis par l’agent qui a recensé votre '
                  'boutique, ou par votre distributeur.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Jetons.encre.withValues(alpha: .58)),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('apercu/connexion.png'),
    );
  });
}

/// Le motif du logo, recopié ici pour que l'aperçu ne dépende pas de l'écran de
/// connexion, qui tire Supabase derrière lui.
class MarqueApercu extends StatelessWidget {
  const MarqueApercu({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        height: 44,
        child: CustomPaint(painter: _Marque()),
      );
}

class _Marque extends CustomPainter {
  @override
  void paint(Canvas toile, Size t) {
    final e = t.width / 40;
    final trait = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2 * e
      ..strokeCap = StrokeCap.round
      ..color = Jetons.jaune;
    final plein = Paint()..color = Jetons.jaune;

    toile.drawPath(
      Path()
        ..moveTo(9 * e, 10 * e)
        ..lineTo(15.2 * e, 10 * e)
        ..lineTo(24.7 * e, 29.5 * e),
      trait,
    );
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
    toile.drawCircle(Offset(17.5 * e, 31.5 * e), 4.2 * e, plein);
  }

  @override
  bool shouldRepaint(covariant CustomPainter ancien) => false;
}
