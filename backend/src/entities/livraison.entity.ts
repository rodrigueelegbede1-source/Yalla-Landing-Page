import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn, ManyToOne, JoinColumn } from 'typeorm';
import { Rupture } from './rupture.entity';
import { Livreur } from './livreur.entity';
import { PointDeVente } from './point-de-vente.entity';

export type StatutLivraison = 'en_cours' | 'terminee' | 'annulee';

@Entity('livraisons')
export class Livraison {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'rupture_id', nullable: true })
  ruptureId?: string;

  @ManyToOne(() => Rupture)
  @JoinColumn({ name: 'rupture_id' })
  rupture?: Rupture;

  @Column({ name: 'livreur_id' })
  livreurId: string;

  @ManyToOne(() => Livreur)
  @JoinColumn({ name: 'livreur_id' })
  livreur: Livreur;

  @Column({ name: 'point_de_vente_id' })
  pointDeVenteId: string;

  @ManyToOne(() => PointDeVente)
  @JoinColumn({ name: 'point_de_vente_id' })
  pointDeVente: PointDeVente;

  @Column({ type: 'enum', enum: ['en_cours', 'terminee', 'annulee'], default: 'en_cours' })
  statut: StatutLivraison;

  @CreateDateColumn({ name: 'date_debut' })
  dateDebut: Date;

  @Column({ name: 'date_fin', type: 'timestamptz', nullable: true })
  dateFin?: Date;

  @Column({ type: 'numeric', precision: 12, scale: 2, default: 0 })
  montant: number;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt: Date;
}
