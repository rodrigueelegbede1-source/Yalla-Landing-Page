import 'package:flutter/material.dart';

/// L'image d'un produit, partout où l'on doit en reconnaître un.
///
/// POURQUOI UNE VIGNETTE PLUTÔT QU'UN SIMPLE `Image.network`. Trois raisons,
/// toutes issues du terrain plutôt que du confort de développement :
///
///   * **Peu de produits auront une photo au début.** Les packshots
///     appartiennent au fabricant, il faut les lui demander, et le pilote ne
///     peut pas attendre. Un carré gris à la place d'une image rend une liste
///     illisible ; une vignette typée, non.
///   * **Le réseau tombe.** Environ un appel sur dix se coupe sur ce projet.
///     Une image qui ne charge pas ne doit pas laisser un trou : elle retombe
///     sur la vignette, et l'écran reste lisible.
///   * **La couleur porte l'information.** La teinte vient de la catégorie, pas
///     du hasard : les boissons, l'épicerie, l'hygiène et le snacking se
///     distinguent d'un coup d'œil dans une liste de trente références, avant
///     même d'avoir lu un mot. C'est ce qui accélère vraiment le repérage.
///
/// Les initiales sont tirées des deux premiers mots utiles du nom, en sautant
/// les mots-outils : « Tomate concentrée Alyssa 400 g » donne TC, pas TD.
class VignetteProduit extends StatelessWidget {
  const VignetteProduit({
    super.key,
    required this.nom,
    this.imageUrl,
    this.categorie,
    this.taille = 44,
  });

  final String nom;
  final String? imageUrl;
  final String? categorie;
  final double taille;

  static const _motsVides = {
    'de', 'du', 'des', 'la', 'le', 'les', 'un', 'une',
    'en', 'à', 'a', 'au', 'aux', 'et', 'avec', 'pour', 'sans',
  };

  /// Une teinte par catégorie. Elles sont choisies pour rester distinctes les
  /// unes des autres tout en s'accordant au vert de la charte, et pour tenir
  /// sur les deux thèmes.
  static const _teintes = {
    'Boissons': Color(0xFF1D6FA8),
    'Épicerie': Color(0xFFB4741A),
    'Hygiène': Color(0xFF2E7D6F),
    'Snacking': Color(0xFF9A3B6B),
  };

  Color _teinte() => _teintes[categorie] ?? const Color(0xFF146B3A);

  String _initiales() {
    final mots = nom
        .split(RegExp(r'[\s/·,-]+'))
        .where((m) => m.isNotEmpty && !_motsVides.contains(m.toLowerCase()))
        .where((m) => RegExp(r'^[\p{L}]', unicode: true).hasMatch(m))
        .toList();

    if (mots.isEmpty) return '?';
    if (mots.length == 1) {
      return mots.first.characters.take(2).toString().toUpperCase();
    }
    return (mots[0].characters.first + mots[1].characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final couleur = _teinte();
    final rayon = BorderRadius.circular(taille * 0.2);

    final repli = Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: rayon,
        border: Border.all(color: couleur.withValues(alpha: 0.22)),
      ),
      alignment: Alignment.center,
      child: Text(
        _initiales(),
        style: TextStyle(
          color: couleur,
          fontWeight: FontWeight.w700,
          fontSize: taille * 0.34,
          letterSpacing: 0.5,
        ),
      ),
    );

    final url = imageUrl;
    if (url == null || url.isEmpty) return repli;

    return ClipRRect(
      borderRadius: rayon,
      child: Image.network(
        url,
        width: taille,
        height: taille,
        fit: BoxFit.cover,
        // Le repli couvre les deux cas : l'image qui n'existe plus, et le
        // réseau qui a coupé pendant le chargement.
        errorBuilder: (_, __, ___) => repli,
        loadingBuilder: (context, enfant, progres) =>
            progres == null ? enfant : repli,
      ),
    );
  }
}
