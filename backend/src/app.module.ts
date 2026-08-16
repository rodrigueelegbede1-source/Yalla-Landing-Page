import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { databaseConfig } from './config/database.config';

import { AuthModule } from './modules/auth/auth.module';
import { PointsDeVenteModule } from './modules/points-de-vente/points-de-vente.module';
import { FabricantsModule } from './modules/fabricants/fabricants.module';
import { ProduitsModule } from './modules/produits/produits.module';
import { LivreursModule } from './modules/livreurs/livreurs.module';
import { RupturesModule } from './modules/ruptures/ruptures.module';
import { LivraisonsModule } from './modules/livraisons/livraisons.module';
import { CaisseModule } from './modules/caisse/caisse.module';
import { NotificationsModule } from './modules/notifications/notifications.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    TypeOrmModule.forRootAsync({ useFactory: databaseConfig }),

    AuthModule,
    PointsDeVenteModule,
    FabricantsModule,
    ProduitsModule,
    LivreursModule,
    RupturesModule,
    LivraisonsModule,
    CaisseModule,
    NotificationsModule,
  ],
})
export class AppModule {}
