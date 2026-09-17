import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/supabase.dart';

/// Où en est le suivi, du point de vue du livreur.
enum EtatSuivi {
  /// Jamais démarré, ou arrêté par le livreur.
  arrete,

  /// La permission a été refusée. Sans elle, aucune course n'est triée par
  /// distance et le distributeur ne voit pas la moto sur sa carte.
  refuse,

  /// Refus définitif : Android ne redemandera plus, il faut passer par les
  /// réglages du téléphone. Le distinguer du refus simple change le message
  /// affiché, et c'est la différence entre un livreur qui s'en sort seul et un
  /// livreur qui appelle au secours.
  refuseDefinitivement,

  /// Suivi actif, mais seulement application ouverte. Le téléphone en poche,
  /// la position cesse de remonter.
  premierPlan,

  /// Suivi actif y compris écran éteint, porté par un service de premier plan.
  arrierePlan,
}

/// Le suivi de position du livreur.
///
/// LE POINT DUR ANNONCÉ AU PLAN, ET CE QUI LE REND DUR. La version précédente
/// interrogeait la position toutes les dix secondes avec un `Timer`. Cela marche
/// tant que l'application est au premier plan, et s'arrête net dès que le
/// livreur range son téléphone, c'est-à-dire pendant toute la course. Android ne
/// tue pas le minuteur bruyamment : il le met en sommeil, et l'application croit
/// suivre alors qu'elle ne suit plus rien. Le distributeur voyait donc une moto
/// figée au dernier carrefour où le livreur avait sorti son téléphone.
///
/// TROIS CHOSES SONT NÉCESSAIRES, et l'absence d'une seule suffit à tout casser.
///
/// 1. **Un service de premier plan.** C'est le seul moyen légitime, depuis
///    Android 8, de continuer à travailler écran éteint. `geolocator` sait en
///    démarrer un via `foregroundNotificationConfig`, ce qui évite d'écrire du
///    Kotlin. Il impose une notification permanente, et c'est tant mieux : le
///    livreur voit qu'il est suivi, et il peut arrêter.
///
/// 2. **La permission d'arrière-plan, demandée en second.** Android 11 et
///    suivants refusent sèchement une demande qui réclame tout d'un coup. Il
///    faut obtenir `whileInUse`, puis seulement demander `always`. Demander les
///    deux ensemble donne un refus définitif, sans boîte de dialogue, et sans
///    aucun moyen de revenir en arrière autrement que par les réglages.
///
/// 3. **Un flux, pas un minuteur.** `getPositionStream` laisse le système
///    grouper les réveils avec ceux des autres applications. Un `Timer.periodic`
///    réveille l'appareil pour lui seul, dix fois par minute, et les
///    constructeurs chinois très présents à Abidjan, Tecno, Infinix, itel, le
///    sanctionnent en tuant purement et simplement l'application.
///
/// CE QUI RESTE HORS DE PORTÉE DU CODE. Ces mêmes constructeurs ajoutent une
/// liste blanche maison, distincte de l'optimisation de batterie standard
/// d'Android. Aucune API ne permet de s'y inscrire. Il faudra le faire à la main
/// sur chaque téléphone de livreur, à la remise de l'appareil.
/// [ouvrirReglages] conduit à l'écran le plus proche.
class SuiviPosition extends ChangeNotifier {
  SuiviPosition({required this.livreurId});

  final String livreurId;

  StreamSubscription<Position>? _flux;
  EtatSuivi _etat = EtatSuivi.arrete;
  DateTime? _dernierEnvoi;
  Position? _dernierePosition;
  int _envois = 0;
  String? _erreur;

  EtatSuivi get etat => _etat;
  DateTime? get dernierEnvoi => _dernierEnvoi;
  Position? get dernierePosition => _dernierePosition;
  int get envois => _envois;
  String? get erreur => _erreur;

  bool get actif => _etat == EtatSuivi.premierPlan || _etat == EtatSuivi.arrierePlan;

  /// Dix mètres. En dessous, le bruit du GPS urbain déclenche des envois pour
  /// une moto à l'arrêt dans un embouteillage du Plateau. Au-dessus, le tracé
  /// devient trop grossier pour estimer une arrivée.
  static const int _filtreMetres = 10;

  /// Démarre le suivi, en demandant les permissions dans le bon ordre.
  ///
  /// [arrierePlan] à faux garde le suivi au premier plan seulement. C'est le
  /// repli quand le livreur refuse, et c'est aussi un état utilisable : mieux
  /// vaut un suivi partiel qu'aucun.
  Future<void> demarrer({bool arrierePlan = true}) async {
    _erreur = null;

    if (!await Geolocator.isLocationServiceEnabled()) {
      _erreur = 'La localisation du téléphone est désactivée.';
      _majEtat(EtatSuivi.refuse);
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      _majEtat(EtatSuivi.refuseDefinitivement);
      return;
    }
    if (permission == LocationPermission.denied) {
      _majEtat(EtatSuivi.refuse);
      return;
    }

    // Deuxième temps seulement : la permission d'arrière-plan. Android affiche
    // ici son propre écran de réglages, hors de l'application, et ne rend
    // jamais de refus immédiat. Inutile donc de traiter son résultat comme une
    // erreur : on relit simplement la permission après coup.
    var enArrierePlan = permission == LocationPermission.always;
    if (arrierePlan && !enArrierePlan) {
      final apres = await Geolocator.requestPermission();
      enArrierePlan = apres == LocationPermission.always;
    }

    await _flux?.cancel();
    _flux = Geolocator.getPositionStream(
      locationSettings: _reglages(enArrierePlan: enArrierePlan),
    ).listen(
      _envoyer,
      onError: (Object e) {
        // Une position perdue n'est pas un incident : le flux reprend de
        // lui-même dès que le signal revient. On ne dérange pas le livreur.
        _erreur = e.toString();
        notifyListeners();
      },
      cancelOnError: false,
    );

    _majEtat(enArrierePlan ? EtatSuivi.arrierePlan : EtatSuivi.premierPlan);
  }

  LocationSettings _reglages({required bool enArrierePlan}) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _filtreMetres,
      );
    }

    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: _filtreMetres,

      // Plafond de temps entre deux positions. Sans lui, une moto arrêtée à un
      // feu n'émet plus rien du tout et le distributeur ne sait pas distinguer
      // « à l'arrêt » de « application tuée ».
      intervalDuration: const Duration(seconds: 30),

      foregroundNotificationConfig: enArrierePlan
          ? const ForegroundNotificationConfig(
              notificationTitle: 'Yalla, course en cours',
              notificationText:
                  'Votre position est partagée avec votre distributeur.',
              notificationChannelName: 'Suivi de course',
              enableWakeLock: true,
              setOngoing: true,
            )
          : null,
    );
  }

  Future<void> _envoyer(Position p) async {
    try {
      // La position courante de `livreurs` est dénormalisée par un trigger : on
      // n'écrit que l'historique, la base synchronise le reste.
      await supabase.from('positions_livreurs').insert({
        'livreur_id': livreurId,
        'position': 'SRID=4326;POINT(${p.longitude} ${p.latitude})',
      });
      _dernierEnvoi = DateTime.now();
      _dernierePosition = p;
      _envois++;
      _erreur = null;
      notifyListeners();
    } catch (e) {
      // Hors réseau, la position est perdue et la suivante arrive dans trente
      // secondes. Une file d'attente locale serait tentante, mais une position
      // vieille de dix minutes rejouée à la reconnexion ferait tracer au
      // distributeur un trajet qui n'a plus lieu d'être.
      _erreur = e.toString();
      notifyListeners();
    }
  }

  Future<void> arreter() async {
    await _flux?.cancel();
    _flux = null;
    _majEtat(EtatSuivi.arrete);
  }

  void _majEtat(EtatSuivi etat) {
    _etat = etat;
    notifyListeners();
  }

  /// Conduit à l'écran des réglages de l'application, d'où la permission
  /// refusée définitivement peut être rétablie.
  Future<void> ouvrirReglages() => Geolocator.openAppSettings();

  /// L'écran des réglages de localisation du système, quand c'est le GPS
  /// lui-même qui est éteint.
  Future<void> ouvrirReglagesLocalisation() => Geolocator.openLocationSettings();

  @override
  void dispose() {
    _flux?.cancel();
    _flux = null;
    super.dispose();
  }
}
