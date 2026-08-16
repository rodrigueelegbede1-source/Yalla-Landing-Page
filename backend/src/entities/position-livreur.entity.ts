import { Entity, PrimaryGeneratedColumn, Column, ManyToOne, JoinColumn } from 'typeorm';
import { Livreur } from './livreur.entity';

@Entity('positions_livreurs')
export class PositionLivreur {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ name: 'livreur_id' })
  livreurId: string;

  @ManyToOne(() => Livreur)
  @JoinColumn({ name: 'livreur_id' })
  livreur: Livreur;

  @Column({ name: 'horodatage', type: 'timestamptz' })
  horodatage: Date;

  // `position` (geography) volontairement absente du mapping — voir LivreursService,
  // qui utilise ST_X/ST_Y en SQL brut pour la lecture et ST_MakePoint pour l'écriture.
}
