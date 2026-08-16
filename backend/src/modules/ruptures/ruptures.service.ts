import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Rupture } from '../../entities/rupture.entity';
import { RealtimeGateway } from '../../gateways/realtime.gateway';

@Injectable()
export class RupturesService {
  constructor(
    @InjectRepository(Rupture) private readonly repo: Repository<Rupture>,
    private readonly realtime: RealtimeGateway,
  ) {}

  // Signalement manuel depuis l'app Point de vente (bouton "Signaler une rupture").
  // Le signalement automatique (vente qui vide un stock) passe par le trigger SQL
  // décrit dans 006_caisse_enregistreuse.sql, pas par ce endpoint.
  async signalerManuellement(pointDeVenteId: string, produitId: string, quantiteDemandee?: number) {
    const rupture = this.repo.create({
      pointDeVenteId,
      produitId,
      quantiteDemandee,
      statut: 'signalee',
      signalementAutomatique: false,
    });
    const saved = await this.repo.save(rupture);

    const [produit] = await this.repo.query(`SELECT fabricant_id AS "fabricantId" FROM produits WHERE id = $1`, [produitId]);
    this.realtime.emettreActiviteReseau({
      type: 'rupture',
      message: 'Nouvelle rupture signalée',
      fabricantId: produit?.fabricantId,
    });

    return saved;
  }

  // Utilisée par l'interface Fabricant : ruptures ouvertes sur son propre catalogue uniquement.
  async findOuvertesParFabricant(fabricantId: string) {
    return this.repo.query(
      `SELECT * FROM v_ruptures_ouvertes WHERE fabricant_id = $1 ORDER BY date_signalement DESC`,
      [fabricantId],
    );
  }

  // Vue Administrateur : toutes les ruptures ouvertes du réseau.
  async findToutesOuvertes() {
    return this.repo.query(`SELECT * FROM v_ruptures_ouvertes ORDER BY date_signalement DESC`);
  }

  /**
   * Coeur de la maquette Livreur : les ruptures ouvertes sur le catalogue du
   * fabricant auquel le livreur est affilié, triées par proximité réelle
   * (index GIST PostGIS), pas par un simple calcul de distance applicatif.
   */
  async findProchesDuLivreur(livreurId: string, limite = 20) {
    return this.repo.query(
      `SELECT ro.*, ST_Distance(ro.position, l.position) AS distance_metres
       FROM v_ruptures_ouvertes ro
       JOIN livreurs l ON l.id = $1
       WHERE ro.fabricant_id = l.fabricant_id
       ORDER BY ro.position <-> l.position
       LIMIT $2`,
      [livreurId, limite],
    );
  }

  async prendreEnCharge(id: string) {
    await this.repo.update(id, { statut: 'prise_en_charge' });
    return this.repo.findOne({ where: { id } });
  }
}
