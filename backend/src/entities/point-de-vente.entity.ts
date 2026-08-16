import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn, ManyToOne, JoinColumn } from 'typeorm';
import { AgentRecenseur } from './agent-recenseur.entity';

export type TypeActivite = 'superette' | 'boutique' | 'kiosque' | 'restaurant_maquis';
export type StatutPointDeVente = 'actif' | 'en_attente_activation' | 'retire';

@Entity('points_de_vente')
export class PointDeVente {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Ajouté par la migration 010 — nullable tant qu'un compte de connexion
  // n'a pas été créé et rattaché à ce point de vente (ex. juste après son
  // enregistrement par un agent recenseur, avant activation).
  @Column({ name: 'utilisateur_id', nullable: true })
  utilisateurId?: string;

  @Column()
  nom: string;

  @Column({ name: 'type_activite', type: 'enum', enum: ['superette', 'boutique', 'kiosque', 'restaurant_maquis'] })
  typeActivite: TypeActivite;

  @Column({ nullable: true })
  adresse?: string;

  @Column()
  commune: string;

  @Column({ default: 'Abidjan' })
  ville: string;

  // `position` (geography) gérée en SQL brut par PointsDeVenteService — voir la méthode create().

  @Column({ name: 'gerant_nom', nullable: true })
  gerantNom?: string;

  @Column({ nullable: true })
  telephone?: string;

  @Column({ type: 'enum', enum: ['actif', 'en_attente_activation', 'retire'], default: 'en_attente_activation' })
  statut: StatutPointDeVente;

  @Column({ name: 'agent_recenseur_id', nullable: true })
  agentRecenseurId?: string;

  @ManyToOne(() => AgentRecenseur)
  @JoinColumn({ name: 'agent_recenseur_id' })
  agentRecenseur?: AgentRecenseur;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt: Date;
}
