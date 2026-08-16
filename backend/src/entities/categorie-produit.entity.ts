import { Entity, PrimaryGeneratedColumn, Column } from 'typeorm';

@Entity('categories_produit')
export class CategorieProduit {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true })
  nom: string;
}
