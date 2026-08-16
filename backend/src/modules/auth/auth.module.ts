import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { Utilisateur } from '../../entities/utilisateur.entity';
import { AuthService } from './auth.service';
import { AuthController } from './auth.controller';
import { JwtStrategy } from './jwt.strategy';

@Module({
  imports: [
    TypeOrmModule.forFeature([Utilisateur]),
    PassportModule,
    JwtModule.register({
      secret: process.env.JWT_SECRET ?? 'change_me_en_production',
      signOptions: { expiresIn: process.env.JWT_EXPIRATION ?? '8h' },
    }),
  ],
  providers: [AuthService, JwtStrategy],
  controllers: [AuthController],
  exports: [AuthService],
})
export class AuthModule {}
