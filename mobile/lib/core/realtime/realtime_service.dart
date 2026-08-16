import 'package:socket_io_client/socket_io_client.dart' as io;
import '../api/api_client.dart';

/// Se connecte à la RealtimeGateway du backend NestJS pour recevoir
/// `livreur:position` et `reseau:activite` en direct — ce sont les mêmes
/// événements que ceux simulés par setInterval() dans les maquettes HTML
/// (flux temps réel de la console Administrateur, carte du Livreur).
class RealtimeService {
  io.Socket? _socket;

  void connecter({required String room}) {
    _socket = io.io(
      apiBaseUrl,
      io.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build(),
    );
    _socket!.connect();
    _socket!.onConnect((_) => _socket!.emit('rejoindre', room));
  }

  void ecouterPositionsLivreurs(void Function(Map<String, dynamic>) onPosition) {
    _socket?.on('livreur:position', (data) => onPosition(Map<String, dynamic>.from(data)));
  }

  void ecouterActiviteReseau(void Function(Map<String, dynamic>) onActivite) {
    _socket?.on('reseau:activite', (data) => onActivite(Map<String, dynamic>.from(data)));
  }

  void deconnecter() {
    _socket?.disconnect();
    _socket?.dispose();
  }
}
