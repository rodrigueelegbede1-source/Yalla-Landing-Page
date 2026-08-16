import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, ManyToOne, JoinColumn, OneToMany } from 'typeorm';
import { PointDeVente } from './point-de-vente.entity';
import { Produit } from './produit.entity';

@Entity('ventes')
export class Vente {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'point_de_vente_id' })
  pointDeVenteId: string;

  @ManyToOne(() => PointDeVente)
  @JoinColumn({ name: 'point_de_vente_id' })
  pointDeVente: PointDeVente;

  @CreateDateColumn({ name: 'date_vente' })
  dateVente: Date;

  @Column({ name: 'montant_total', type: 'numeric', precision: 12, scale: 2, default: 0 })
  montantTotal: number;

  @OneToMany(() => LigneVente, (ligne) => ligne.vente)
  lignes: LigneVente[];
}

@Entity('lignes_vente')
export class LigneVente {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'vente_id' })
  venteId: string;

  @ManyToOne(() => Vente, (vente) => vente.lignes)
  @JoinColumn({ name: 'vente_id' })
  vente: Vente;

  @Column({ name: 'produit_id', nullable: true })
  produitId?: string;

  @ManyToOne(() => Produit)
  @JoinColumn({ name: 'produit_id' })
  produit?: Produit;

  @Column({ name: 'produit_libre_nom', nullable: true })
  produitLibreNom?: string;

  @Column()
  quantite: number;

  @Column({ name: 'prix_unitaire', type: 'numeric', precision: 12, scale: 2 })
  prixUnitaire: number;
}
