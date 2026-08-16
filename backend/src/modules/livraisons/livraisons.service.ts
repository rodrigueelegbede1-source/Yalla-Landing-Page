import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Livraison } from '../../entities/livraison.entity';
import { CreateLivraisonDto } from './dto/create-livraison.dto';

@Injectable()
export class LivraisonsService {
  constructor(
    @InjectRepository(Livraison) private readonly repo: Repository<Livraison>,
  ) {}

  // Le livreur démarre une course depuis l'écran "Détail" de la maquette Livreur.
  // `livreurId` est l'idMetier porté par le token JWT (voir AuthService.resoudreIdMetier).
  async demarrer(livreurId: string, dto: CreateLivraisonDto) {
    const livraison = this.repo.create({
      livreurId,
      ruptureId: dto.ruptureId,
      pointDeVenteId: dto.pointDeVenteId,
      statut: 'en_cours',
      montant: dto.montant ?? 0,
    });
    return this.repo.save(livraison);
  }

  // Marquer une livraison terminée déclenche automatiquement, côté base de données,
  // la résolution de la rupture liée (trigger `trg_livraisons_resout_rupture`, migration 005).
  async terminer(id: string, montant?: number) {
    const livraison = await this.repo.findOne({ where: { id } });
    if (!livraison) throw new NotFoundException('Livraison introuvable');
    livraison.statut = 'terminee';
    livraison.dateFin = new Date();
    if (montant !== undefined) livraison.montant = montant;
    return this.repo.save(livraison);
  }

  async annuler(id: string) {
    await this.repo.update(id, { statut: 'annulee', dateFin: new Date() });
    return this.repo.findOne({ where: { id } });
  }

  // Historique — maquette Livreur, onglet Historique (livraisons de la semaine).
  async findParLivreur(livreurId: string) {
    return this.repo.find({ where: { livreurId }, order: { dateDebut: 'DESC' } });
  }
}
