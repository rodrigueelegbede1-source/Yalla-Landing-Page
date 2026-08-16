import { IsUUID, IsOptional, IsInt, Min } from 'class-validator';

export class SignalerRuptureDto {
  @IsUUID()
  produitId: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  quantiteDemandee?: number;
}
