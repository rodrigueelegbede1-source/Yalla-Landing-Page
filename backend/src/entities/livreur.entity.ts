import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn, JoinColumn, OneToOne, ManyToOne } from 'typeorm';
import { Utilisateur } from './utilisateur.entity';
import { Fabricant } from './fabricant.entity';

@Entity('livreurs')
export class Livreur {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'utilisateur_id' })
  utilisateurId: string;

  @OneToOne(() => Utilisateur)
  @JoinColumn({ name: 'utilisateur_id' })
  utilisateur: Utilisateur;

  @Column({ name: 'fabricant_id' })
  fabricantId: string;

  @ManyToOne(() => Fabricant)
  @JoinColumn({ name: 'fabricant_id' })
  fabricant: Fabricant;

  @Column({ name: 'en_ligne', default: false })
  enLigne: boolean;

  // La colonne géographique `position` n'est pas mappée directement ici :
  // elle est lue/écrite via des requêtes SQL brutes dans LivreursService,
  // pour éviter les pièges de mapping ORM <-> PostGIS. Voir position-livreur.entity.ts.
  @Column({ name: 'position_maj_le', type: 'timestamptz', nullable: true })
  positionMajLe?: Date;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt: Date;
}
