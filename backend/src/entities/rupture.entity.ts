import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn, ManyToOne, JoinColumn } from 'typeorm';
import { PointDeVente } from './point-de-vente.entity';
import { Produit } from './produit.entity';

export type StatutRupture = 'signalee' | 'prise_en_charge' | 'resolue';

@Entity('ruptures')
export class Rupture {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'point_de_vente_id' })
  pointDeVenteId: string;

  @ManyToOne(() => PointDeVente)
  @JoinColumn({ name: 'point_de_vente_id' })
  pointDeVente: PointDeVente;

  @Column({ name: 'produit_id' })
  produitId: string;

  @ManyToOne(() => Produit)
  @JoinColumn({ name: 'produit_id' })
  produit: Produit;

  @Column({ name: 'quantite_demandee', nullable: true })
  quantiteDemandee?: number;

  @Column({ type: 'enum', enum: ['signalee', 'prise_en_charge', 'resolue'], default: 'signalee' })
  statut: StatutRupture;

  @Column({ name: 'signalement_automatique', default: false })
  signalementAutomatique: boolean;

  @CreateDateColumn({ name: 'date_signalement' })
  dateSignalement: Date;

  @Column({ name: 'date_resolution', type: 'timestamptz', nullable: true })
  dateResolution?: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt: Date;
}
