import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn, ManyToOne, JoinColumn } from 'typeorm';
import { Fabricant } from './fabricant.entity';
import { CategorieProduit } from './categorie-produit.entity';

@Entity('produits')
export class Produit {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'fabricant_id' })
  fabricantId: string;

  @ManyToOne(() => Fabricant)
  @JoinColumn({ name: 'fabricant_id' })
  fabricant: Fabricant;

  @Column()
  nom: string;

  @Column()
  reference: string;

  @Column({ name: 'categorie_id', nullable: true })
  categorieId?: string;

  @ManyToOne(() => CategorieProduit)
  @JoinColumn({ name: 'categorie_id' })
  categorie?: CategorieProduit;

  @Column({ name: 'image_url', nullable: true })
  imageUrl?: string;

  @Column({ default: true })
  disponible: boolean;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt: Date;
}
