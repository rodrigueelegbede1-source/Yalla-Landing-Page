import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Produit } from '../../entities/produit.entity';
import { CreateProduitDto } from './dto/create-produit.dto';

@Injectable()
export class ProduitsService {
  constructor(@InjectRepository(Produit) private readonly repo: Repository<Produit>) {}

  // Catalogue d'un fabricant — maquette Fabricant, onglet Catalogue.
  findParFabricant(fabricantId: string) {
    return this.repo.find({ where: { fabricantId }, relations: ['categorie'] });
  }

  // Catalogue global par catégorie — maquette Point de vente, écran "Signaler une rupture".
  async findCatalogueGlobal(categorieId?: string) {
    const where = categorieId ? { categorieId } : {};
    return this.repo.find({ where, relations: ['fabricant', 'categorie'] });
  }

  async ajouter(fabricantId: string, dto: CreateProduitDto) {
    const produit = this.repo.create({ ...dto, fabricantId });
    return this.repo.save(produit);
  }

  async retirer(id: string) {
    const produit = await this.repo.findOne({ where: { id } });
    if (!produit) throw new NotFoundException('Produit introuvable');
    await this.repo.delete(id);
    return { ok: true };
  }
}
