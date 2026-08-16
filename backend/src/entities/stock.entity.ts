import { Entity, PrimaryGeneratedColumn, Column, ManyToOne, JoinColumn } from 'typeorm';
import { PointDeVente } from './point-de-vente.entity';
import { Produit } from './produit.entity';

@Entity('stocks')
export class Stock {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'point_de_vente_id' })
  pointDeVenteId: string;

  @ManyToOne(() => PointDeVente)
  @JoinColumn({ name: 'point_de_vente_id' })
  pointDeVente: PointDeVente;

  @Column({ name: 'produit_id', nullable: true })
  produitId?: string;

  @ManyToOne(() => Produit)
  @JoinColumn({ name: 'produit_id' })
  produit?: Produit;

  @Column({ name: 'produit_libre_nom', nullable: true })
  produitLibreNom?: string;

  @Column({ default: 0 })
  quantite: number;

  @Column({ name: 'date_maj', type: 'timestamptz' })
  dateMaj: Date;
}
