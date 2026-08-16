import { IsString, IsOptional, IsEnum, IsNumber, IsUUID, Min, Max } from 'class-validator';
import { TypeActivite } from '../../../entities/point-de-vente.entity';

export class CreatePointDeVenteDto {
  @IsString()
  nom: string;

  @IsEnum(['superette', 'boutique', 'kiosque', 'restaurant_maquis'])
  typeActivite: TypeActivite;

  @IsOptional()
  @IsString()
  adresse?: string;

  @IsString()
  commune: string;

  @IsOptional()
  @IsString()
  ville?: string;

  @IsNumber()
  @Min(-90)
  @Max(90)
  latitude: number;

  @IsNumber()
  @Min(-180)
  @Max(180)
  longitude: number;

  @IsOptional()
  @IsString()
  gerantNom?: string;

  @IsOptional()
  @IsString()
  telephone?: string;

  @IsOptional()
  @IsUUID()
  agentRecenseurId?: string;
}
