import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Fabricant } from '../../entities/fabricant.entity';

@Injectable()
export class FabricantsService {
  constructor(@InjectRepository(Fabricant) private readonly repo: Repository<Fabricant>) {}

  findAll() {
    return this.repo.find();
  }

  async findOne(id: string) {
    const fabricant = await this.repo.findOne({ where: { id } });
    if (!fabricant) throw new NotFoundException('Fabricant introuvable');
    return fabricant;
  }

  // Réseau de points de vente attribués — maquette Fabricant, écran Accueil (mini-carte).
  async findReseauAttribue(fabricantId: string) {
    return this.repo.query(
      `SELECT pdv.id, pdv.nom, pdv.commune, pdv.statut,
              ST_Y(pdv.position::geometry) AS latitude, ST_X(pdv.position::geometry) AS longitude
       FROM points_de_vente pdv
       JOIN attributions_reseau ar ON ar.point_de_vente_id = pdv.id
       WHERE ar.fabricant_id = $1`,
      [fabricantId],
    );
  }

  // Chiffre d'affaires temps réel — s'appuie sur la vue définie en migration 008.
  async chiffreAffaires(fabricantId: string) {
    const rows = await this.repo.query(
      `SELECT * FROM v_chiffre_affaires_par_fabricant WHERE fabricant_id = $1`,
      [fabricantId],
    );
    return rows[0] ?? { fabricantId, chiffreAffaires: 0 };
  }

  async attribuerPointDeVente(fabricantId: string, pointDeVenteId: string) {
    await this.repo.query(
      `INSERT INTO attributions_reseau (fabricant_id, point_de_vente_id)
       VALUES ($1, $2) ON CONFLICT (fabricant_id, point_de_vente_id) DO NOTHING`,
      [fabricantId, pointDeVenteId],
    );
    return { ok: true };
  }
}
