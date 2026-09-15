import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn, JoinColumn, OneToOne, ManyToOne } from 'typeorm';
import { Utilisateur } from './utilisateur.entity';
import { Distributeur } from './distributeur.entity';

@Entity('livreurs')
export class Livreur {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'utilisateur_id' })
  utilisateurId: string;

  @OneToOne(() => Utilisateur)
  @JoinColumn({ name: 'utilisateur_id' })
  utilisateur: Utilisateur;

  // Depuis la migration 011, le livreur dépend du distributeur et non plus du
  // fabricant : il n'a jamais été l'employé d'une marque, mais de celui qui
  // distribue. Le cas du fabricant qui livre lui-même reste couvert, via son
  // distributeur d'auto-distribution.
  @Column({ name: 'distributeur_id' })
  distributeurId: string;

  @ManyToOne(() => Distributeur)
  @JoinColumn({ name: 'distributeur_id' })
  distributeur: Distributeur;

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
