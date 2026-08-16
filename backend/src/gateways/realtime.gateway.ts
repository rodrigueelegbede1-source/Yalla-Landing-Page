import { WebSocketGateway, WebSocketServer, SubscribeMessage } from '@nestjs/websockets';
import { Server } from 'socket.io';

/**
 * Diffuse en temps réel :
 *  - `livreur:position` — nouvelle position d'un livreur (carte Administrateur / Fabricant)
 *  - `reseau:activite` — événement générique pour le flux temps réel de la console
 *    Administrateur (rupture signalée, livraison démarrée/terminée, etc.)
 *
 * Les clients rejoignent une "room" par fabricant (`fabricant:<id>`) ou la room
 * `reseau:global` pour l'administrateur, afin de ne recevoir que ce qui les concerne —
 * cohérent avec la règle métier "un fabricant ne voit que son propre catalogue".
 */
@WebSocketGateway({ cors: { origin: '*' } })
export class RealtimeGateway {
  @WebSocketServer()
  server: Server;

  @SubscribeMessage('rejoindre')
  rejoindreRoom(client: any, room: string) {
    client.join(room);
  }

  emettrePositionLivreur(fabricantId: string, payload: { livreurId: string; latitude: number; longitude: number; horodatage: Date }) {
    this.server.to(`fabricant:${fabricantId}`).emit('livreur:position', payload);
    this.server.to('reseau:global').emit('livreur:position', payload);
  }

  emettreActiviteReseau(evenement: { type: string; message: string; fabricantId?: string }) {
    this.server.to('reseau:global').emit('reseau:activite', evenement);
    if (evenement.fabricantId) {
      this.server.to(`fabricant:${evenement.fabricantId}`).emit('reseau:activite', evenement);
    }
  }
}
