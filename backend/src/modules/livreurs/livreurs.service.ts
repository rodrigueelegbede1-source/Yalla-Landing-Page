import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Livreur } from '../../entities/livreur.entity';
import { RealtimeGateway } from '../../gateways/realtime.gateway';

@Injectable()
export class LivreursService {
  constructor(
    @InjectRepository(Livreur) private readonly repo: Repository<Livreur>,
    private readonly realtime: RealtimeGateway,
  ) {}

  /**
   * Historise une position (table positions_livreurs) — le trigger SQL
   * `trg_positions_livreurs_sync` (migration 003) se charge de synchroniser
   * livreurs.position / position_maj_le automatiquement. On diffuse ensuite
   * l'événement en temps réel aux clients concernés.
   *
   * `livreurId` est désormais l'idMetier porté par le token JWT (voir
   * AuthService.resoudreIdMetier) — plus besoin de le résoudre ici à partir
   * de l'utilisateur à chaque appel.
   *
   * Fréquence attendue côté app mobile : ~10 s en course, ~60 s à l'arrêt,
   * rien hors ligne (voir Yalla_Stack_Technique.md).
   */
  async enregistrerPosition(livreurId: string, latitude: number, longitude: number) {
    const livreur = await this.repo.findOne({ where: { id: livreurId } });
    if (!livreur) throw new NotFoundException('Livreur introuvable');

    await this.repo.query(
      `INSERT INTO positions_livreurs (livreur_id, position, horodatage)
       VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography, now())`,
      [livreurId, longitude, latitude],
    );

    this.realtime.emettrePositionLivreur(livreur.fabricantId, {
      livreurId,
      latitude,
      longitude,
      horodatage: new Date(),
    });

    return { ok: true };
  }

  async setEnLigne(livreurId: string, enLigne: boolean) {
    await this.repo.update(livreurId, { enLigne });
    return { ok: true, enLigne };
  }

  async findByFabricant(fabricantId: string) {
    return this.repo.query(
      `SELECT l.id, u.nom, l.en_ligne AS "enLigne",
              ST_Y(l.position::geometry) AS latitude, ST_X(l.position::geometry) AS longitude,
              l.position_maj_le AS "positionMajLe"
       FROM livreurs l
       JOIN utilisateurs u ON u.id = l.utilisateur_id
       WHERE l.fabricant_id = $1
       ORDER BY u.nom`,
      [fabricantId],
    );
  }
}
