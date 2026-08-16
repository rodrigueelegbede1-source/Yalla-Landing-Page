import { IsUUID, IsArray, ValidateNested, IsOptional, IsInt, Min, IsNumber, IsString } from 'class-validator';
import { Type } from 'class-transformer';

class LigneVenteDto {
  @IsOptional()
  @IsUUID()
  produitId?: string;

  @IsOptional()
  @IsString()
  produitLibreNom?: string;

  @IsInt()
  @Min(1)
  quantite: number;

  @IsNumber()
  prixUnitaire: number;
}

export class CreateVenteDto {
  @IsUUID()
  pointDeVenteId: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => LigneVenteDto)
  lignes: LigneVenteDto[];
}
