import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn } from 'typeorm';

// Six rôles depuis la migration 011 : le distributeur est l'acteur qui reçoit
// une rupture et qui agit dessus. Le fabricant, lui, la voit en lecture.
export type RoleUtilisateur =
  | 'administrateur'
  | 'fabricant'
  | 'distributeur'
  | 'livreur'
  | 'point_de_vente'
  | 'agent_recenseur';

@Entity('utilisateurs')
export class Utilisateur {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  nom: string;

  @Column({ unique: true })
  telephone: string;

  @Column({ nullable: true, unique: true })
  email?: string;

  @Column({ name: 'mot_de_passe_hash' })
  motDePasseHash: string;

  @Column({ type: 'enum', enum: ['administrateur', 'fabricant', 'distributeur', 'livreur', 'point_de_vente', 'agent_recenseur'] })
  role: RoleUtilisateur;

  @Column({ name: 'derniere_connexion', type: 'timestamptz', nullable: true })
  derniereConnexion?: Date;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt: Date;
}
