import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, ManyToOne, JoinColumn } from 'typeorm';
import { Fabricant } from './fabricant.entity';
import { PointDeVente } from './point-de-vente.entity';
import { Distributeur } from './distributeur.entity';

/**
 * Le triplet qui porte tout le routage : ce fabricant couvre cette boutique,
 * par la main de ce distributeur. Une même boutique peut être desservie par un
 * distributeur pour une marque et par un autre pour une autre marque, ce qui est
 * la réalité de la distribution de proximité à Abidjan.
 */
@Entity('attributions_reseau')
export class AttributionReseau {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'fabricant_id' })
  fabricantId: string;

  @ManyToOne(() => Fabricant)
  @JoinColumn({ name: 'fabricant_id' })
  fabricant: Fabricant;

  @Column({ name: 'point_de_vente_id' })
  pointDeVenteId: string;

  @ManyToOne(() => PointDeVente)
  @JoinColumn({ name: 'point_de_vente_id' })
  pointDeVente: PointDeVente;

  // Nul tant qu'aucun distributeur n'a été désigné pour ce couple. La rupture
  // naît alors sans destinataire et n'est visible qu'après escalade.
  @Column({ name: 'distributeur_id', nullable: true })
  distributeurId?: string;

  @ManyToOne(() => Distributeur, { nullable: true })
  @JoinColumn({ name: 'distributeur_id' })
  distributeur?: Distributeur;

  @CreateDateColumn({ name: 'date_attribution' })
  dateAttribution: Date;
}
