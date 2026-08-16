import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Vente, LigneVente } from '../../entities/vente.entity';
import { Stock } from '../../entities/stock.entity';
import { CaisseService } from './caisse.service';
import { CaisseController } from './caisse.controller';
import { RealtimeGateway } from '../../gateways/realtime.gateway';

@Module({
  imports: [TypeOrmModule.forFeature([Vente, LigneVente, Stock])],
  providers: [CaisseService, RealtimeGateway],
  controllers: [CaisseController],
})
export class CaisseModule {}
