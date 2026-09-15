import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn, JoinColumn, OneToOne, ManyToOne } from 'typeorm';
import { Utilisateur } from './utilisateur.entity';
import { Fabricant } from './fabricant.entity';

export type StatutDistributeur = 'actif' | 'suspendu';

/**
 * Sixième acteur de la chaîne, introduit par la migration 011.
 *
 * C'est lui qui reçoit une rupture et qui agit dessus. Le fabricant, lui, la
 * voit en lecture sur son seul catalogue.
 *
 * Les trois cas de terrain tiennent dans cette seule table :
 *  - distributeur affilié      → `fabricantId` renseigné, `autoDistribution` false
 *  - distributeur indépendant  → `fabricantId` nul, il travaille plusieurs marques
 *  - fabricant qui distribue   → `fabricantId` renseigné, `autoDistribution` true
 *
 * Grâce au troisième cas, aucun code ne traite le fabricant-livreur en
 * exception : tout passe toujours par un distributeur.
 */
@Entity('distributeurs')
export class Distributeur {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Nullable, à la différence des autres tables de rôle : un distributeur
  // d'auto-distribution n'a pas de compte propre (le fabricant a déjà le sien),
  // et un distributeur recensé sur le terrain peut ne pas encore être inscrit.
  @Column({ name: 'utilisateur_id', nullable: true })
  utilisateurId?: string;

  @OneToOne(() => Utilisateur, { nullable: true })
  @JoinColumn({ name: 'utilisateur_id' })
  utilisateur?: Utilisateur;

  @Column({ name: 'fabricant_id', nullable: true })
  fabricantId?: string;

  @ManyToOne(() => Fabricant, { nullable: true })
  @JoinColumn({ name: 'fabricant_id' })
  fabricant?: Fabricant;

  @Column()
  nom: string;

  @Column({ nullable: true })
  telephone?: string;

  @Column({ name: 'auto_distribution', default: false })
  autoDistribution: boolean;

  @Column({ type: 'enum', enum: ['actif', 'suspendu'], default: 'actif' })
  statut: StatutDistributeur;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt: Date;
}
