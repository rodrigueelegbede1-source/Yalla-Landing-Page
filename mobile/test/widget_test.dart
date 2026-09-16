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
