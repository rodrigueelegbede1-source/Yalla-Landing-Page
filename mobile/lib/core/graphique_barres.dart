import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

class SerieGraphique {
  const SerieGraphique({required this.nom, required this.couleur});

  final String nom;
  final Color couleur;
}

class PointGraphique {
  const PointGraphique({required this.libelle, required this.valeurs});

  final String libelle;
  final List<int> valeurs;
}

class GraphiqueBarres extends StatelessWidget {
  const GraphiqueBarres({
    super.key,
    required this.titre,
    required this.series,
    required this.points,
  });

  final String titre;
  final List<SerieGraphique> series;
  final List<PointGraphique> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('$titre\nAucune donnée sur la période.'),
        ),
      );
    }

    final hauteur =
        math.max(156.0, points.length * (series.length * 11.0 + 12));
    final resume = points
        .map((point) => '${point.libelle}: ${point.valeurs.join(', ')}')
        .join('; ');

    return Semantics(
      label: '$titre. ${series.map((serie) => serie.nom).join(', ')}. $resume',
      child: Card(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titre,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: series
                    .map((serie) => _LegendeGraphique(serie: serie))
                    .toList(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: hauteur,
                width: double.infinity,
                child: CustomPaint(
                  painter: _PeintreBarres(series: series, points: points),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendeGraphique extends StatelessWidget {
  const _LegendeGraphique({required this.serie});

  final SerieGraphique serie;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: serie.couleur,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(serie.nom, style: const TextStyle(fontSize: 11)),
        ],
      );
}

class _PeintreBarres extends CustomPainter {
  const _PeintreBarres({required this.series, required this.points});

  final List<SerieGraphique> series;
  final List<PointGraphique> points;

  static const _margeGauche = 92.0;
  static const _margeDroite = 30.0;
  static const _margeHaute = 8.0;
  static const _margeBasse = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    final aire = size.width - _margeGauche - _margeDroite;
    if (aire <= 0 || points.isEmpty) return;

    final maximum = points
        .expand((point) => point.valeurs)
        .fold<int>(1, (max, valeur) => valeur > max ? valeur : max);
    final hautGraphique = size.height - _margeHaute - _margeBasse;
    final hauteurLigne = hautGraphique / points.length;
    final hauteurBarre = math.min(
      9.0,
      (hauteurLigne - 4) / math.max(1, series.length),
    );
    const espaceBarres = 2.0;
    final styleAxe = TextStyle(
      color: Jetons.encre.withValues(alpha: .48),
      fontSize: 9,
    );
    final grille = Paint()
      ..color = Jetons.encre.withValues(alpha: .09)
      ..strokeWidth = 1;

    for (var index = 0; index <= 2; index++) {
      final ratio = index / 2;
      final x = _margeGauche + aire * ratio;
      canvas.drawLine(
        Offset(x, _margeHaute),
        Offset(x, size.height - _margeBasse),
        grille,
      );
      _dessinerTexte(
        canvas,
        '${(maximum * ratio).round()}',
        Offset(x - 10, size.height - _margeBasse + 3),
        styleAxe,
        largeurMax: 22,
      );
    }

    for (var indexPoint = 0; indexPoint < points.length; indexPoint++) {
      final point = points[indexPoint];
      final centreY = _margeHaute + hauteurLigne * (indexPoint + .5);
      final hauteurGroupe = series.length * hauteurBarre +
          math.max(0, series.length - 1) * espaceBarres;
      final debutY = centreY - hauteurGroupe / 2;
      _dessinerTexte(
        canvas,
        point.libelle,
        Offset(0, centreY - 6),
        const TextStyle(color: Jetons.encre, fontSize: 10),
        largeurMax: _margeGauche - 8,
      );

      for (var indexSerie = 0; indexSerie < series.length; indexSerie++) {
        final serie = series[indexSerie];
        final valeur =
            indexSerie < point.valeurs.length ? point.valeurs[indexSerie] : 0;
        final largeur = aire * valeur / maximum;
        final y = debutY + indexSerie * (hauteurBarre + espaceBarres);
        final rectangle = RRect.fromRectAndRadius(
          Rect.fromLTWH(_margeGauche, y, math.max(0, largeur), hauteurBarre),
          const Radius.circular(3),
        );
        canvas.drawRRect(rectangle, Paint()..color = serie.couleur);
        _dessinerTexte(
          canvas,
          '$valeur',
          Offset(_margeGauche + largeur + 4, y - 1),
          const TextStyle(color: Jetons.encre, fontSize: 9),
          largeurMax: _margeDroite - 4,
        );
      }
    }
  }

  void _dessinerTexte(
    Canvas canvas,
    String texte,
    Offset position,
    TextStyle style, {
    required double largeurMax,
  }) {
    final peintre = TextPainter(
      text: TextSpan(text: texte, style: style),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: largeurMax);
    peintre.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant _PeintreBarres oldDelegate) =>
      oldDelegate.series != series || oldDelegate.points != points;
}
