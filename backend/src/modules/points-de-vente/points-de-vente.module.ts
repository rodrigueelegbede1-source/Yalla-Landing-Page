import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { PointDeVente } from '../../entities/point-de-vente.entity';
import { PointsDeVenteService } from './points-de-vente.service';
import { PointsDeVenteController } from './points-de-vente.controller';

@Module({
  imports: [TypeOrmModule.forFeature([PointDeVente])],
  providers: [PointsDeVenteService],
  controllers: [PointsDeVenteController],
  exports: [PointsDeVenteService],
})
export class PointsDeVenteModule {}
