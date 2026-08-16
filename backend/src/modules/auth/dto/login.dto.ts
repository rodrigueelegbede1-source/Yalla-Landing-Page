import { IsString, MinLength } from 'class-validator';

export class LoginDto {
  @IsString()
  telephone: string;

  @IsString()
  @MinLength(6)
  motDePasse: string;
}
