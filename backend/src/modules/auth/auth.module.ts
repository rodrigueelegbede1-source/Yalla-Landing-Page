import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JwtModule } from '@nestjs/jwt';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { PassportModule } from '@nestjs/passport';
import { Utilisateur } from '../../entities/utilisateur.entity';
import { AuthService } from './auth.service';
import { AuthController } from './auth.controller';
import { JwtStrategy } from './jwt.strategy';

@Module({
  imports: [
    TypeOrmModule.forFeature([Utilisateur]),
    PassportModule,
    // `registerAsync` et non `register` : c'est un correctif, pas une question de style.
    //
    // Un `JwtModule.register({ secret: process.env.JWT_SECRET })` est évalué au
    // chargement de ce fichier, donc AVANT que le `ConfigModule.forRoot()` de
    // app.module ait lu backend/.env. La signature retombait alors sur le secret
    // de repli, pendant que JwtStrategy, instanciée plus tard par l'injection de
    // dépendances, lisait la vraie valeur. Résultat observé au premier démarrage
    // contre une vraie base : /auth/login délivrait bien un token, et toutes les
    // routes protégées répondaient 401 sur ce même token, sans message explicite.
    //
    // La fabrique asynchrone résout le secret au moment de l'injection, à la même
    // source et au même instant que la stratégie. Les deux ne peuvent plus diverger.
    JwtModule.registerAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: config.get<string>('JWT_SECRET') ?? 'change_me_en_production',
        signOptions: { expiresIn: config.get<string>('JWT_EXPIRATION') ?? '8h' },
      }),
    }),
  ],
  providers: [AuthService, JwtStrategy],
  controllers: [AuthController],
  exports: [AuthService],
})
export class AuthModule {}
