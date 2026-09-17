import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase.dart';

/// Le temps réel de Yalla, branché aux écrans.
///
/// La publication existait côté base depuis la migration `realtime_et_cron`,
/// mais rien ne s'y abonnait : le carnet du distributeur se rafraîchissait à la
/// main, en tirant la liste vers le bas. Sur une rupture, ce délai est le
/// produit lui-même. Une boutique d'Adjamé qui attend deux heures parce que le
/// distributeur n'a pas pensé à rafraîchir, c'est exactement la situation que
/// Yalla prétend supprimer.
///
/// CE QUE CE FICHIER NE FAIT PAS, ET POURQUOI. Il ne transporte pas les données
/// modifiées jusqu'à l'écran. Il émet un simple compteur, et l'écran recharge sa
/// requête. C'est un choix, pas un raccourci :
///
///   * les écrans lisent des VUES (`v_carnet_distributeur`, `v_mes_courses`)
///     qui joignent cinq tables et calculent des colonnes. Un évènement de
///     modification sur `ruptures` ne porte que la ligne brute, sans le nom du
///     produit, sans la commune, sans le compte à rebours. Il faudrait
///     reconstruire la vue en Dart, et la reconstruire faux ;
///   * le rechargement est une requête indexée sur quelques dizaines de lignes.
///     Sur un réseau abidjanais, la latence tient dans la centaine de
///     millisecondes.
///
/// La règle de sécurité tient d'elle-même : la diffusion respecte les politiques
/// RLS, et le rechargement passe par la vue, elle aussi sous RLS. Un
/// distributeur n'est donc jamais réveillé par une rupture qu'il n'a pas le
/// droit de voir, et s'il l'était, la requête ne lui rendrait rien.
class SignalTempsReel extends ChangeNotifier {
  SignalTempsReel(this._tables) {
    _ouvrir();
  }

  final List<String> _tables;
  RealtimeChannel? _canal;

  /// Incrémenté à chaque changement reçu. Les écrans n'en lisent pas la valeur,
  /// ils écoutent simplement la notification.
  int _revision = 0;
  int get revision => _revision;

  /// Faux tant que le canal n'a pas confirmé son abonnement, ou après une
  /// coupure. L'écran l'affiche, parce qu'un utilisateur qui croit sa liste
  /// vivante alors qu'elle est figée prend de mauvaises décisions.
  bool _connecte = false;
  bool get connecte => _connecte;

  void _ouvrir() {
    // Un nom de canal par jeu de tables : deux écrans qui écoutent les mêmes
    // tables partagent le canal plutôt que d'en ouvrir deux.
    final canal = supabase.channel('yalla:${_tables.join("-")}');

    for (final table in _tables) {
      canal.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) {
          _revision++;
          notifyListeners();
        },
      );
    }

    canal.subscribe((statut, [erreur]) {
      final avant = _connecte;
      _connecte = statut == RealtimeSubscribeStatus.subscribed;

      // Une reconnexion doit provoquer un rechargement : pendant la coupure,
      // des ruptures ont pu naître sans que personne en soit averti. C'est le
      // cas fréquent en Côte d'Ivoire, où la 3G tombe en passant un carrefour.
      if (_connecte && !avant) _revision++;
      notifyListeners();
    });

    _canal = canal;
  }

  @override
  void dispose() {
    final canal = _canal;
    _canal = null;
    if (canal != null) unawaited(supabase.removeChannel(canal));
    super.dispose();
  }
}

/// Le signal des ruptures et des livraisons : ce que regardent le distributeur
/// et le livreur.
final tempsReelCoursesProvider = ChangeNotifierProvider.autoDispose(
  (ref) {
    final signal = SignalTempsReel(const ['ruptures', 'livraisons']);
    ref.onDispose(signal.dispose);
    return signal;
  },
);

/// Le signal de la boutique. Elle ne suit que ses propres ruptures : la
/// diffusion est filtrée par RLS, donc l'abonnement à `ruptures` ne lui apporte
/// que les siennes.
final tempsReelBoutiqueProvider = ChangeNotifierProvider.autoDispose(
  (ref) {
    final signal = SignalTempsReel(const ['ruptures', 'stocks']);
    ref.onDispose(signal.dispose);
    return signal;
  },
);
