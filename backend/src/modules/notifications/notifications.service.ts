import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Notification, SondageOption, SondageReponse } from '../../entities/notification.entity';
import { CreateNotificationDto } from './dto/create-notification.dto';
import { RealtimeGateway } from '../../gateways/realtime.gateway';

@Injectable()
export class NotificationsService {
  constructor(
    @InjectRepository(Notification) private readonly notifications: Repository<Notification>,
    @InjectRepository(SondageOption) private readonly options: Repository<SondageOption>,
    @InjectRepository(SondageReponse) private readonly reponses: Repository<SondageReponse>,
    private readonly realtime: RealtimeGateway,
  ) {}

  // Composition et envoi — maquette Administrateur, écran "Notifications & annonces".
  // L'envoi FCM réel (push effectif vers les téléphones) reste à brancher ici une fois
  // les tokens d'appareil stockés côté utilisateurs (hors périmètre de ce schéma v1).
  async envoyer(emetteurId: string, dto: CreateNotificationDto) {
    const notification = await this.notifications.save(
      this.notifications.create({
        emetteurId,
        type: dto.type,
        titre: dto.titre,
        message: dto.message,
        cible: dto.cible,
      }),
    );

    if (dto.type === 'sondage' && dto.options?.length) {
      const opts = dto.options.map((libelle) => this.options.create({ notificationId: notification.id, libelle }));
      await this.options.save(opts);
    }

    this.realtime.emettreActiviteReseau({
      type: dto.type,
      message: `Nouvelle notification : ${dto.titre}`,
    });

    return notification;
  }

  async repondreSondage(notificationId: string, pointDeVenteId: string, optionChoisieId: string) {
    const reponse = this.reponses.create({ notificationId, pointDeVenteId, optionChoisieId });
    return this.reponses.save(reponse);
  }

  // Notifications reçues par un point de vente — maquette Point de vente, onglet Notifs.
  async findRecuesParPointDeVente() {
    return this.notifications.find({
      where: [{ cible: 'reseau_complet' }, { cible: 'points_de_vente' }],
      order: { dateEnvoi: 'DESC' },
      relations: ['options'],
    });
  }
}
