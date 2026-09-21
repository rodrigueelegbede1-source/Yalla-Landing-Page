/// La coque visuelle : canevas vert, feuille blanche, tuiles, trait illustré.
///
/// C'EST LA GRAMMAIRE REPRISE À LA RÉFÉRENCE, et elle tient en une phrase : un
/// bloc de marque plein en haut, une feuille de contenu à grand rayon qui le
/// chevauche vers le haut, et à l'intérieur des cartes douces et une grille de
/// tuiles d'accès rapide.
///
/// POURQUOI CE CHEVAUCHEMENT MARCHE, et pourquoi il ne coûte rien : il donne au
/// contenu une frontière franche sans tracer un seul filet. L'œil comprend
/// « ici c'est le produit, là c'est mon travail » avant d'avoir lu un mot, et
/// cela survit au plein soleil, là où un filet gris de un pixel disparaît.
///
/// TOUT EST DIRECTIONNEL : aucun `left` ni `right` de ce fichier. L'arabe
/// retourne l'interface, et un rayon posé du mauvais côté se voit immédiatement.
library;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Le canevas vert du haut, avec sa bande illustrée et, posée dessus, la
/// feuille de contenu qui remonte par-dessus lui.
///
/// `hauteurCanevas` est la hauteur du vert AVANT chevauchement. La feuille
/// remonte de `chevauchement`, si bien que le vert visible au-dessus d'elle
/// vaut la différence. On règle donc une seule valeur pour tout l'écran.
class CoqueVerte extends StatelessWidget {
  const CoqueVerte({
    super.key,
    required this.entete,
    required this.enfant,
    this.bandeIllustree = true,
  });

  /// Ce qui vit dans le vert : salutation, nom, état du jour.
  final Widget entete;

  /// Ce qui vit dans la feuille blanche.
  final Widget enfant;

  final bool bandeIllustree;

  /// La hauteur du décor, et la garde que le texte doit respecter au-dessus.
  static const _hauteurBande = 74.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        // Un dégradé très court, du vert 800 au vert 700. Un aplat unique
        // paraît plat sur une grande surface ; un dégradé marqué ferait
        // bannière publicitaire. Deux crans d'écart suffisent à donner de la
        // matière sans qu'on sache dire pourquoi.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Jetons.vert800, Jetons.vert700],
        ),
      ),
      child: Column(
        children: [
          // LE CANEVAS SE DIMENSIONNE SUR SON CONTENU, il n'a plus de hauteur
          // fixe. Une hauteur en dur était juste sur l'écran où elle avait été
          // réglée, et fausse partout ailleurs : une encoche plus haute, un nom
          // de boutique sur deux lignes ou la taille de police du système
          // poussaient le texte dans le décor. Le premier rendu l'a montré tout
          // de suite, la salutation posée en plein sur les toits.
          Stack(
            children: [
              // La bande illustrée est DERRIÈRE l'en-tête, collée au bas du
              // canevas. Le contenu réserve exactement sa hauteur au-dessus de
              // lui, si bien qu'aucun mot ne la croise jamais : un trait d'un
              // pixel derrière une lettre la rend illisible sur une dalle bon
              // marché, et la moitié du parc l'est.
              if (bandeIllustree)
                const PositionedDirectional(
                  bottom: 0, start: 0, end: 0, height: _hauteurBande,
                  child: IgnorePointer(child: BandeMarche()),
                ),
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.only(
                      bottom: bandeIllustree ? _hauteurBande : 18),
                  child: entete,
                ),
              ),
            ],
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Jetons.creme,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(Jetons.rFeuille),
                ),
                boxShadow: Jetons.ombreFeuille,
              ),
              clipBehavior: Clip.antiAlias,
              // LE CHEVAUCHEMENT EST UNE ILLUSION, et il vaut mieux ainsi. La
              // première version remontait vraiment la feuille d'une vingtaine
              // de points, ce qui laissait la même bande de vert nue en bas de
              // l'écran : visible dès le premier rendu. Les coins arrondis et
              // l'ombre suffisent à donner la profondeur, puisque le vert
              // apparaît dans les deux encoches du haut. Rien à compenser, et
              // rien qui dépasse.
              child: enfant,
            ),
          ),
        ],
      ),
    );
  }
}

/// La bande illustrée du canevas.
///
/// La référence dessine des montagnes et des nuages, parce qu'elle vend un
/// parc national. YALLA VEND UNE RUE COMMERÇANTE : la bande dessine une
/// enfilade d'échoppes avec leurs auvents, motif qu'un boutiquier d'Adjamé
/// reconnaît sans qu'on le lui explique. Le décor doit parler du métier, sinon
/// il n'est que du décor.
///
/// Peinte au `CustomPainter` plutôt qu'importée en image : quelques traits
/// coûtent zéro octet dans l'APK et restent nets à toutes les densités, là où
/// un PNG à trois résolutions pèse et bave.
class BandeMarche extends StatelessWidget {
  const BandeMarche({super.key});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _PeintreMarche(), size: Size.infinite);
}

class _PeintreMarche extends CustomPainter {
  @override
  void paint(Canvas toile, Size taille) {
    final trait = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      // Très discret : la bande est une texture, pas un dessin qu'on regarde.
      // À 22 % elle se devine et ne concurrence rien.
      ..color = Colors.white.withValues(alpha: .22);

    final sol = taille.height - 10;

    // Le sol, qui pose tout le reste.
    toile.drawLine(Offset(0, sol), Offset(taille.width, sol), trait);

    // Une enfilade d'échoppes de largeurs inégales : trois boutiques
    // identiques feraient motif de papier peint, pas rue.
    const largeurs = [58.0, 44.0, 70.0, 50.0, 62.0, 40.0, 66.0, 48.0];
    var x = -18.0;
    var i = 0;
    while (x < taille.width + 20) {
      final l = largeurs[i % largeurs.length];
      final h = 30.0 + (i % 3) * 9;
      final haut = sol - h;

      // La façade.
      toile.drawRect(Rect.fromLTRB(x, haut, x + l, sol), trait);

      // L'auvent, en pente, qui donne la silhouette de marché.
      final auvent = Path()
        ..moveTo(x - 5, haut)
        ..lineTo(x + l / 2, haut - 13)
        ..lineTo(x + l + 5, haut);
      toile.drawPath(auvent, trait);

      // L'ouverture, seulement une échoppe sur deux : toutes ouvertes, le
      // motif redevient régulier.
      if (i.isEven) {
        toile.drawRect(
          Rect.fromLTRB(x + l * 0.3, sol - h * 0.55, x + l * 0.7, sol),
          trait,
        );
      }

      x += l + 12;
      i += 1;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter ancien) => false;
}

/// La salutation du canevas : bonjour, qui, et où.
class SalutationCanevas extends StatelessWidget {
  const SalutationCanevas({
    super.key,
    required this.salutation,
    required this.nom,
    this.detail,
    this.actions = const [],
  });

  final String salutation;
  final String nom;
  final String? detail;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(22, 10, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  salutation,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: Colors.white.withValues(alpha: .78),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  nom,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    color: Jetons.blanc,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    detail!,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.35,
                      color: Colors.white.withValues(alpha: .72),
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// La tuile d'accès rapide, cœur de la grille de la référence.
///
/// POURQUOI ELLE VAUT MIEUX QU'UN ONGLET DE PLUS pour ce produit : un
/// boutiquier debout, interrompu, ne balaye pas une barre de cinq icônes de
/// vingt-quatre points. Une tuile fait cent points de côté, porte un mot en
/// clair, et son compteur se lit de loin.
///
/// La pastille du compteur est CORAIL et non jaune : le jaune est réservé à
/// l'action principale de l'écran, et deux accents qui se disputent l'attention
/// n'en font aucun.
class TuileAction extends StatelessWidget {
  const TuileAction({
    super.key,
    required this.icone,
    required this.libelle,
    required this.onTap,
    this.compteur = 0,
    this.teinte,
  });

  final IconData icone;
  final String libelle;
  final VoidCallback onTap;
  final int compteur;

  /// La teinte du badge d'icône. Laissée nulle, elle vaut le vert de la marque.
  /// Une teinte par usage aide à retrouver une tuile de mémoire, après quelques
  /// jours, sans relire les libellés.
  final Color? teinte;

  @override
  Widget build(BuildContext context) {
    final couleur = teinte ?? Jetons.vert700;

    return Material(
      color: Jetons.blanc,
      borderRadius: BorderRadius.circular(Jetons.rTuile),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Jetons.rTuile),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Jetons.rTuile),
            boxShadow: Jetons.ombreCarte,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        // Un fond très pâle de la teinte, comme la référence :
                        // l'icône pleine sur un carré coloré ferait bouton
                        // d'application, pas raccourci.
                        color: couleur.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icone, size: 24, color: couleur),
                    ),
                    if (compteur > 0)
                      PositionedDirectional(
                        top: -5,
                        end: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          constraints: const BoxConstraints(minWidth: 20),
                          decoration: BoxDecoration(
                            color: Jetons.alerte,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Jetons.blanc, width: 2),
                          ),
                          child: Text(
                            compteur > 99 ? '99+' : '$compteur',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Jetons.blanc,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  libelle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: Jetons.encre,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La grille de tuiles. Trois colonnes, comme la référence : à quatre, le
/// libellé ne tient plus sur un écran de 5 pouces et se coupe.
class GrilleActions extends StatelessWidget {
  const GrilleActions({super.key, required this.tuiles});

  final List<TuileAction> tuiles;

  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 11,
        crossAxisSpacing: 11,
        // 0,95 faisait déborder la tuile de six points sur un écran de 360 :
        // badge de 46, écart de 9 et deux lignes de libellé ne tenaient pas.
        // Le premier rendu l'a montré par ses barres de débordement.
        childAspectRatio: 0.84,
        children: tuiles,
      );
}

/// La carte douce : blanche, grand rayon, ombre basse.
class CarteDouce extends StatelessWidget {
  const CarteDouce({
    super.key,
    required this.enfant,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.accent,
  });

  final Widget enfant;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Un liseré de tête, pour la carte qui attend un geste. Une seule par écran.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final corps = Container(
      decoration: BoxDecoration(
        color: Jetons.blanc,
        borderRadius: BorderRadius.circular(Jetons.rCarte),
        boxShadow: Jetons.ombreCarte,
        border: accent == null
            ? null
            : BorderDirectional(start: BorderSide(color: accent!, width: 4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: enfant),
    );

    if (onTap == null) return corps;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Jetons.rCarte),
        child: corps,
      ),
    );
  }
}

/// Le titre d'un bloc dans la feuille. Repris de la référence, où chaque
/// section s'ouvre par un mot en gras et un lien discret à l'opposé.
class TitreBloc extends StatelessWidget {
  const TitreBloc(this.titre, {super.key, this.action, this.onAction});

  final String titre;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 11, top: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(titre, style: Theme.of(context).textTheme.titleMedium),
            ),
            if (action != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(action!, style: const TextStyle(fontSize: 13.5)),
              ),
          ],
        ),
      );
}

/// Un bouton rond translucide, pour les actions du canevas vert. Une icône nue
/// sur le vert se touche mal ; un disque à peine visible donne la cible sans
/// alourdir l'en-tête.
class BoutonCanevas extends StatelessWidget {
  const BoutonCanevas({
    super.key,
    required this.icone,
    required this.onTap,
    this.infobulle,
  });

  final IconData icone;
  final VoidCallback onTap;
  final String? infobulle;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onTap,
        tooltip: infobulle,
        icon: Icon(icone, size: 21, color: Colors.white.withValues(alpha: .92)),
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: .14),
          minimumSize: const Size(42, 42),
          shape: const CircleBorder(),
        ),
      );
}
