import { WebSocketGateway, WebSocketServer, SubscribeMessage } from '@nestjs/websockets';
import { Server } from 'socket.io';

/**
 * Diffuse en temps réel :
 *  - `livreur:position` — nouvelle position d'un livreur (carte Administrateur / Fabricant / Distributeur)
 *  - `reseau:activite` — événement générique pour le flux temps réel de la console
 *    Administrateur (rupture signalée, prise en charge, escaladée, expirée)
 *
 * Les clients rejoignent une "room" par fabricant (`fabricant:<id>`), par
 * distributeur (`distributeur:<id>`), ou la room `reseau:global` pour
 * l'administrateur, afin de ne recevoir que ce qui les concerne — cohérent avec
 * la règle métier "un fabricant ne voit que son propre catalogue".
 *
 * Une rupture escaladée concerne plusieurs distributeurs à la fois : l'appelant
 * passe alors la liste complète dans `distributeurIds`, calculée à partir de
 * `v_acces_rupture_distributeur`, plutôt qu'une room « commune » qui diffuserait
 * à des distributeurs ne travaillant pas la marque concernée.
 */
@WebSocketGateway({ cors: { origin: '*' } })
export class RealtimeGateway {
  @WebSocketServer()
  server: Server;

  @SubscribeMessage('rejoindre')
  rejoindreRoom(client: any, room: string) {
    client.join(room);
  }

  emettrePositionLivreur(
    destinataires: { fabricantId?: string; distributeurId?: string },
    payload: { livreurId: string; latitude: number; longitude: number; horodatage: Date },
  ) {
    if (destinataires.distributeurId) {
      this.server.to(`distributeur:${destinataires.distributeurId}`).emit('livreur:position', payload);
    }
    if (destinataires.fabricantId) {
      this.server.to(`fabricant:${destinataires.fabricantId}`).emit('livreur:position', payload);
    }
    this.server.to('reseau:global').emit('livreur:position', payload);
  }

  emettreActiviteReseau(evenement: {
    type: string;
    message: string;
    fabricantId?: string;
    distributeurId?: string;
    distributeurIds?: string[];
  }) {
    this.server.to('reseau:global').emit('reseau:activite', evenement);

    if (evenement.fabricantId) {
      this.server.to(`fabricant:${evenement.fabricantId}`).emit('reseau:activite', evenement);
    }

    const cibles = new Set(evenement.distributeurIds ?? []);
    if (evenement.distributeurId) cibles.add(evenement.distributeurId);
    for (const id of cibles) {
      this.server.to(`distributeur:${id}`).emit('reseau:activite', evenement);
    }
  }
}
