import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Livreur } from '../../entities/livreur.entity';
import { LivreursService } from './livreurs.service';
import { LivreursController } from './livreurs.controller';
import { RealtimeGateway } from '../../gateways/realtime.gateway';

@Module({
  imports: [TypeOrmModule.forFeature([Livreur])],
  providers: [LivreursService, RealtimeGateway],
  controllers: [LivreursController],
  exports: [LivreursService],
})
export class LivreursModule {}
