import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, ManyToOne, JoinColumn } from 'typeorm';
import { Livraison } from './livraison.entity';

export type FournisseurPaiement = 'orange_ci' | 'mtn_ci' | 'wave' | 'moov' | 'djamo';
export type StatutTransaction = 'en_attente' | 'confirmee' | 'echouee';

@Entity('transactions')
export class Transaction {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'livraison_id' })
  livraisonId: string;

  @ManyToOne(() => Livraison)
  @JoinColumn({ name: 'livraison_id' })
  livraison: Livraison;

  @Column({ type: 'numeric', precision: 12, scale: 2 })
  montant: number;

  @Column({ type: 'enum', enum: ['orange_ci', 'mtn_ci', 'wave', 'moov', 'djamo'] })
  fournisseur: FournisseurPaiement;

  @Column({ type: 'enum', enum: ['en_attente', 'confirmee', 'echouee'], default: 'en_attente' })
  statut: StatutTransaction;

  @Column({ name: 'reference_cinetpay', nullable: true })
  referenceCinetpay?: string;

  @CreateDateColumn()
  date: Date;
}
