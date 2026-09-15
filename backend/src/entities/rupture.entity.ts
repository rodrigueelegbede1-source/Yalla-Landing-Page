import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn, ManyToOne, JoinColumn } from 'typeorm';
import { PointDeVente } from './point-de-vente.entity';
import { Produit } from './produit.entity';
import { Distributeur } from './distributeur.entity';
import { Livreur } from './livreur.entity';

// `non_servie` est le statut terminal ajouté par la migration 011 : personne n'a
// pris la rupture avant expiration. Sans lui, une rupture abandonnée resterait
// ouverte à vie et le taux de service ne serait pas calculable.
export type StatutRupture = 'signalee' | 'prise_en_charge' | 'resolue' | 'non_servie';

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

  @Column({ type: 'enum', enum: ['signalee', 'prise_en_charge', 'resolue', 'non_servie'], default: 'signalee' })
  statut: StatutRupture;

  // Destinataire de la rupture, résolu à l'insertion par le trigger SQL
  // `trg_ruptures_resout_destinataire` (migration 011) et non par ce code :
  // la rupture émise automatiquement par la caisse ne passe jamais par NestJS.
  // Nul quand aucun distributeur n'est encore désigné pour cette boutique et
  // cette marque ; elle partira alors au cercle élargi dès l'escalade.
  @Column({ name: 'distributeur_id', nullable: true })
  distributeurId?: string;

  @ManyToOne(() => Distributeur, { nullable: true })
  @JoinColumn({ name: 'distributeur_id' })
  distributeur?: Distributeur;

  // Le livreur qui a effectivement pris la course. Renseigné en même temps que
  // le passage en `prise_en_charge`, par un UPDATE conditionnel qui garantit un
  // seul gagnant (voir RupturesService.prendreEnCharge).
  @Column({ name: 'livreur_id', nullable: true })
  livreurId?: string;

  @ManyToOne(() => Livreur, { nullable: true })
  @JoinColumn({ name: 'livreur_id' })
  livreur?: Livreur;

  @Column({ name: 'signalement_automatique', default: false })
  signalementAutomatique: boolean;

  @CreateDateColumn({ name: 'date_signalement' })
  dateSignalement: Date;

  @Column({ name: 'date_prise_en_charge', type: 'timestamptz', nullable: true })
  datePriseEnCharge?: Date;

  // Horodatage de l'ouverture au cercle élargi. Nul tant que seule l'entité
  // attribuée peut voir la rupture.
  @Column({ name: 'escaladee_le', type: 'timestamptz', nullable: true })
  escaladeeLe?: Date;

  // Date de clôture, quelle qu'en soit l'issue : livraison effectuée (`resolue`)
  // ou expiration (`non_servie`).
  @Column({ name: 'date_resolution', type: 'timestamptz', nullable: true })
  dateResolution?: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt: Date;
}
