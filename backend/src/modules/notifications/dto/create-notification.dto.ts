import { IsString, IsEnum, IsOptional, IsArray } from 'class-validator';
import { TypeNotification, CibleNotification } from '../../../entities/notification.entity';

export class CreateNotificationDto {
  @IsEnum(['notification', 'splash_publicitaire', 'sondage'])
  type: TypeNotification;

  @IsString()
  titre: string;

  @IsString()
  message: string;

  @IsEnum(['reseau_complet', 'fabricants', 'points_de_vente', 'livreurs'])
  cible: CibleNotification;

  // Uniquement pour type = 'sondage'.
  @IsOptional()
  @IsArray()
  options?: string[];
}
