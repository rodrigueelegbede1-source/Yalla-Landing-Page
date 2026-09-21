/// Éléments d'interface partagés par les écrans.
///
/// Ils étaient recopiés dans chaque fichier, ce qui a fini par produire quatre
/// variantes du même état vide, avec quatre marges différentes.
library;

import 'package:flutter/material.dart';

/// L'état vide, qui doit dire pourquoi c'est vide et non se contenter de l'être.
///
/// « Aucune course » n'apprend rien. « Vos boutiques sont servies, les nouvelles
/// ruptures apparaîtront ici » dit à la fois l'état et ce qui va se passer.
class EtatVide extends StatelessWidget {
  const EtatVide({
    super.key,
    required this.icone,
    required this.titre,
    required this.message,
    this.action,
    this.onAction,
  });

  final IconData icone;
  final String titre;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => ListView(
        children: [
          const SizedBox(height: 80),
          Icon(icone, size: 56),
          const SizedBox(height: 20),
          Text(titre,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, height: 1.5)),
          ),
          if (action != null) ...[
            const SizedBox(height: 24),
            Center(
              child: FilledButton.tonal(onPressed: onAction, child: Text(action!)),
            ),
          ],
        ],
      );
}

/// Étiquette colorée, pour un état qui doit se lire d'un coup d'œil sur une moto.
class Etiquette extends StatelessWidget {
  const Etiquette({super.key, required this.texte, required this.couleur});

  final String texte;
  final Color couleur;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(texte,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: couleur)),
      );
}

/// Titre de section avec son compte à droite.
class TitreSection extends StatelessWidget {
  const TitreSection(this.texte, {super.key, this.detail});

  final String texte;
  final String? detail;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(texte,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            if (detail != null) Text(detail!, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
}

/// Pastille d'état du temps réel : la liste est-elle vivante ou figée.
class PastilleTempsReel extends StatelessWidget {
  const PastilleTempsReel({super.key, required this.connecte, this.surVert = false});

  final bool connecte;

  /// `surVert` : la pastille vit désormais dans le canevas de marque, où un
  /// vert sur vert ne se voit pas et un gris disparaît. Sur fond vert, c'est
  /// donc un disque translucide avec un point blanc ou éteint.
  final bool surVert;

  @override
  Widget build(BuildContext context) {
    final message = connecte
        ? 'Mise à jour en direct'
        : 'Hors direct, tirez la liste pour rafraîchir';

    if (!surVert) {
      return Tooltip(
        message: message,
        child: Icon(
          connecte ? Icons.bolt : Icons.bolt_outlined,
          size: 18,
          color: connecte ? Colors.green : Colors.grey,
        ),
      );
    }

    return Tooltip(
      message: message,
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .14),
          shape: BoxShape.circle,
        ),
        child: Icon(
          connecte ? Icons.bolt : Icons.bolt_outlined,
          size: 19,
          // Le jaune du logo pour « ça vit », blanc éteint pour « ça ne remonte
          // plus ». C'est le seul endroit du canevas où le jaune apparaît, et
          // il y signifie exactement une chose : le direct fonctionne.
          color: connecte ? const Color(0xFFFFE500) : Colors.white.withValues(alpha: .45),
        ),
      ),
    );
  }
}
