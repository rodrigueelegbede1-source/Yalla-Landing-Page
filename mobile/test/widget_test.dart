import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_mobile/core/telephone.dart';

/// Verrouille la correspondance entre la normalisation Dart et la fonction SQL
/// `normaliser_telephone()`. Si les deux divergent, l'utilisateur saisit un
/// numéro valide, l'application construit une adresse qui ne correspond à aucun
/// compte, et la connexion échoue sans que rien n'explique pourquoi.
void main() {
  group('normaliserTelephone', () {
    test('accepte les formes de saisie courantes', () {
      const attendu = '2250706303030';
      expect(normaliserTelephone('0706303030'), attendu);
      expect(normaliserTelephone('07 06 30 30 30'), attendu);
      expect(normaliserTelephone('+225 07 06 30 30 30'), attendu);
      expect(normaliserTelephone('+2250706303030'), attendu);
      expect(normaliserTelephone('002250706303030'), attendu);
      expect(normaliserTelephone('225 07 06 30 30 30'), attendu);
    });

    test('ignore la ponctuation', () {
      expect(normaliserTelephone('07-06.30/30(30)'), '2250706303030');
    });

    /// Les fixes ivoiriens commencent par 25 ou 27, pas par zéro.
    ///
    /// Une version antérieure n'ajoutait l'indicatif qu'aux numéros commençant
    /// par zéro, héritage du plan de numérotation d'avant 2021. Conséquence :
    /// un boutiquier avec un mobile était accepté, un boutiquier avec un fixe
    /// refusé, sans que rien n'explique la différence. Découvert en inscrivant
    /// un fabricant dont le seul numéro est un fixe de Treichville.
    test('accepte les numéros fixes, qui ne commencent pas par zéro', () {
      const attendu = '2252721219000';
      expect(normaliserTelephone('2721219000'), attendu);
      expect(normaliserTelephone('27 21 21 90 00'), attendu);
      expect(normaliserTelephone('+225 27 21 21 90 00'), attendu);
      expect(telephoneValide('27 21 21 90 00'), isTrue);

      // Fixe de l'intérieur du pays, préfixe 25.
      expect(normaliserTelephone('25 30 64 00 00'), '2252530640000');
    });

    /// L'ancien format à huit chiffres reste refusé, et c'est délibéré : il
    /// n'est plus attribué depuis 2021, et deviner le préfixe manquant
    /// donnerait un mauvais numéro une fois sur deux.
    test('refuse l\'ancien format à huit chiffres', () {
      expect(telephoneValide('21 21 90 00'), isFalse);
      expect(telephoneValide('+225 21 21 90 00'), isFalse);
    });
  });

  group('emailTechnique', () {
    test('dérive la même adresse quelle que soit la saisie', () {
      expect(emailTechnique('07 06 30 30 30'), '2250706303030@yalla.ci');
      expect(emailTechnique('+2250706303030'), '2250706303030@yalla.ci');
    });
  });

  group('telephoneValide', () {
    test('accepte un numéro ivoirien complet', () {
      expect(telephoneValide('0706303030'), isTrue);
      expect(telephoneValide('+225 07 06 30 30 30'), isTrue);
    });

    test('refuse une saisie incomplète', () {
      expect(telephoneValide('070630'), isFalse);
      expect(telephoneValide(''), isFalse);
      expect(telephoneValide('33612345678'), isFalse);
    });
  });
}
