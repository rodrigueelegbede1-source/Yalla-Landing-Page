import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, ManyToOne, JoinColumn, OneToMany } from 'typeorm';
import { Utilisateur } from './utilisateur.entity';
import { PointDeVente } from './point-de-vente.entity';

export type TypeNotification = 'notification' | 'splash_publicitaire' | 'sondage';
export type CibleNotification = 'reseau_complet' | 'fabricants' | 'points_de_vente' | 'livreurs';

@Entity('notifications')
export class Notification {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'emetteur_id' })
  emetteurId: string;

  @ManyToOne(() => Utilisateur)
  @JoinColumn({ name: 'emetteur_id' })
  emetteur: Utilisateur;

  @Column({ type: 'enum', enum: ['notification', 'splash_publicitaire', 'sondage'], default: 'notification' })
  type: TypeNotification;

  @Column()
  titre: string;

  @Column()
  message: string;

  @Column({ type: 'enum', enum: ['reseau_complet', 'fabricants', 'points_de_vente', 'livreurs'], default: 'reseau_complet' })
  cible: CibleNotification;

  @CreateDateColumn({ name: 'date_envoi' })
  dateEnvoi: Date;

  @OneToMany(() => SondageOption, (option) => option.notification)
  options: SondageOption[];
}

@Entity('sondage_options')
export class SondageOption {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'notification_id' })
  notificationId: string;

  @ManyToOne(() => Notification, (n) => n.options)
  @JoinColumn({ name: 'notification_id' })
  notification: Notification;

  @Column()
  libelle: string;
}

@Entity('sondage_reponses')
export class SondageReponse {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'notification_id' })
  notificationId: string;

  @Column({ name: 'point_de_vente_id' })
  pointDeVenteId: string;

  @ManyToOne(() => PointDeVente)
  @JoinColumn({ name: 'point_de_vente_id' })
  pointDeVente: PointDeVente;

  @Column({ name: 'option_choisie_id' })
  optionChoisieId: string;

  @ManyToOne(() => SondageOption)
  @JoinColumn({ name: 'option_choisie_id' })
  optionChoisie: SondageOption;

  @CreateDateColumn({ name: 'date_reponse' })
  dateReponse: Date;
}
