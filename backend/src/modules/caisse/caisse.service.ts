import { BadRequestException, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, Repository } from 'typeorm';
import { Vente } from '../../entities/vente.entity';
import { Stock } from '../../entities/stock.entity';
import { CreateVenteDto } from './dto/create-vente.dto';
import { RealtimeGateway } from '../../gateways/realtime.gateway';

@Injectable()
export class CaisseService {
  constructor(
    @InjectRepository(Vente) private readonly ventes: Repository<Vente>,
    @InjectRepository(Stock) private readonly stocks: Repository<Stock>,
    private readonly dataSource: DataSource,
    private readonly realtime: RealtimeGateway,
  ) {}

  /**
   * Enregistre une vente et ses lignes dans une transaction. Le décrément de
   * stock et le déclenchement automatique de rupture sont entièrement gérés
   * par le trigger SQL `trg_lignes_vente_decremente_stock` (migration 006) —
   * ce service n'a pas à réimplémenter cette règle métier, seulement à
   * insérer les lignes et lire les ruptures qui en résultent pour la diffusion
   * temps réel.
   */
  async enregistrerVente(dto: CreateVenteDto) {
    if (dto.lignes.length === 0) {
      throw new BadRequestException('Une vente doit contenir au moins une ligne');
    }

    return this.dataSource.transaction(async (manager) => {
      const montantTotal = dto.lignes.reduce((total, l) => total + l.quantite * l.prixUnitaire, 0);

      const vente = await manager.query(
        `INSERT INTO ventes (point_de_vente_id, montant_total) VALUES ($1, $2) RETURNING id`,
        [dto.pointDeVenteId, montantTotal],
      );
      const venteId = vente[0].id;

      const ruptureIdsAvant = await this.idsRupturesOuvertes(manager, dto.pointDeVenteId);

      for (const ligne of dto.lignes) {
        await manager.query(
          `INSERT INTO lignes_vente (vente_id, produit_id, produit_libre_nom, quantite, prix_unitaire)
           VALUES ($1, $2, $3, $4, $5)`,
          [venteId, ligne.produitId ?? null, ligne.produitLibreNom ?? null, ligne.quantite, ligne.prixUnitaire],
        );
      }

      const ruptureIdsApres = await this.idsRupturesOuvertes(manager, dto.pointDeVenteId);
      const nouvellesRuptures = ruptureIdsApres.filter((id: string) => !ruptureIdsAvant.includes(id));

      if (nouvellesRuptures.length > 0) {
        this.realtime.emettreActiviteReseau({
          type: 'rupture_automatique',
          message: `${nouvellesRuptures.length} rupture(s) déclenchée(s) automatiquement par une vente`,
        });
      }

      return { venteId, montantTotal, nouvellesRuptures };
    });
  }

  private async idsRupturesOuvertes(manager: any, pointDeVenteId: string): Promise<string[]> {
    const rows = await manager.query(
      `SELECT id FROM ruptures WHERE point_de_vente_id = $1 AND statut IN ('signalee', 'prise_en_charge')`,
      [pointDeVenteId],
    );
    return rows.map((r: any) => r.id);
  }

  async stockDuPointDeVente(pointDeVenteId: string) {
    return this.stocks.find({ where: { pointDeVenteId } });
  }
}
