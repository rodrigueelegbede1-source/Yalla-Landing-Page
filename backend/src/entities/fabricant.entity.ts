import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn, JoinColumn, OneToOne } from 'typeorm';
import { Utilisateur } from './utilisateur.entity';

@Entity('fabricants')
export class Fabricant {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'utilisateur_id' })
  utilisateurId: string;

  @OneToOne(() => Utilisateur)
  @JoinColumn({ name: 'utilisateur_id' })
  utilisateur: Utilisateur;

  @Column()
  nom: string;

  @Column({ type: 'enum', enum: ['actif', 'suspendu'], default: 'actif' })
  statut: 'actif' | 'suspendu';

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt: Date;
}
