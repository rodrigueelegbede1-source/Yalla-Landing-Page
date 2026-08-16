import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { PointDeVente } from '../../entities/point-de-vente.entity';
import { CreatePointDeVenteDto } from './dto/create-point-de-vente.dto';

@Injectable()
export class PointsDeVenteService {
  constructor(
    @InjectRepository(PointDeVente) private readonly repo: Repository<PointDeVente>,
  ) {}

  /**
   * `position` est une colonne geography — on l'écrit via ST_MakePoint en SQL brut
   * plutôt que via le mapping d'entité TypeORM, pour rester au plus près du type
   * PostGIS natif défini dans la migration 003.
   */
  async create(dto: CreatePointDeVenteDto): Promise<PointDeVente> {
    const rows = await this.repo.query(
      `INSERT INTO points_de_vente
        (nom, type_activite, adresse, commune, ville, position, gerant_nom, telephone, agent_recenseur_id)
       VALUES ($1, $2, $3, $4, COALESCE($5, 'Abidjan'),
        ST_SetSRID(ST_MakePoint($6, $7), 4326)::geography, $8, $9, $10)
       RETURNING *`,
      [
        dto.nom,
        dto.typeActivite,
        dto.adresse ?? null,
        dto.commune,
        dto.ville ?? null,
        dto.longitude,
        dto.latitude,
        dto.gerantNom ?? null,
        dto.telephone ?? null,
        dto.agentRecenseurId ?? null,
      ],
    );
    return this.findOne(rows[0].id);
  }

  async findOne(id: string) {
    const rows = await this.repo.query(
      `SELECT id, nom, type_activite AS "typeActivite", adresse, commune, ville,
              ST_Y(position::geometry) AS latitude, ST_X(position::geometry) AS longitude,
              gerant_nom AS "gerantNom", telephone, statut, agent_recenseur_id AS "agentRecenseurId",
              created_at AS "createdAt", updated_at AS "updatedAt"
       FROM points_de_vente WHERE id = $1`,
      [id],
    );
    if (rows.length === 0) throw new NotFoundException('Point de vente introuvable');
    return rows[0];
  }

  async findByCommune(commune?: string) {
    if (commune) {
      return this.repo.query(
        `SELECT id, nom, commune, statut, ST_Y(position::geometry) AS latitude, ST_X(position::geometry) AS longitude
         FROM points_de_vente WHERE commune = $1 ORDER BY nom`,
        [commune],
      );
    }
    return this.repo.query(
      `SELECT id, nom, commune, statut, ST_Y(position::geometry) AS latitude, ST_X(position::geometry) AS longitude
       FROM points_de_vente ORDER BY nom`,
    );
  }

  async activer(id: string) {
    await this.repo.update(id, { statut: 'actif' });
    return this.findOne(id);
  }

  async retirer(id: string) {
    await this.repo.update(id, { statut: 'retire' });
    return this.findOne(id);
  }
}
