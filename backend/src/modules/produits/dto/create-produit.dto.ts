import { IsString, IsOptional, IsUUID } from 'class-validator';

export class CreateProduitDto {
  @IsString()
  nom: string;

  @IsString()
  reference: string;

  @IsOptional()
  @IsUUID()
  categorieId?: string;

  @IsOptional()
  @IsString()
  imageUrl?: string;
}
