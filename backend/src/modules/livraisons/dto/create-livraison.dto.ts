import { IsUUID, IsOptional, IsNumber } from 'class-validator';

export class CreateLivraisonDto {
  @IsOptional()
  @IsUUID()
  ruptureId?: string;

  @IsUUID()
  pointDeVenteId: string;

  @IsOptional()
  @IsNumber()
  montant?: number;
}
