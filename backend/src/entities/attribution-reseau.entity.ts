import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, ManyToOne, JoinColumn } from 'typeorm';
import { Fabricant } from './fabricant.entity';
import { PointDeVente } from './point-de-vente.entity';

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

  @CreateDateColumn({ name: 'date_attribution' })
  dateAttribution: Date;
}
