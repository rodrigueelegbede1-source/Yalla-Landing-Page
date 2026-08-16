import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn, JoinColumn, OneToOne } from 'typeorm';
import { Utilisateur } from './utilisateur.entity';

@Entity('agents_recenseurs')
export class AgentRecenseur {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'utilisateur_id' })
  utilisateurId: string;

  @OneToOne(() => Utilisateur)
  @JoinColumn({ name: 'utilisateur_id' })
  utilisateur: Utilisateur;

  @Column()
  secteur: string;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt: Date;
}
