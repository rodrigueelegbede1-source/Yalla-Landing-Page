import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Rupture } from '../../entities/rupture.entity';
import { RupturesService } from './ruptures.service';
import { EscaladeService } from './escalade.service';
import { RupturesController } from './ruptures.controller';
import { RealtimeGateway } from '../../gateways/realtime.gateway';

@Module({
  imports: [TypeOrmModule.forFeature([Rupture])],
  providers: [RupturesService, EscaladeService, RealtimeGateway],
  controllers: [RupturesController],
  exports: [RupturesService, EscaladeService],
})
export class RupturesModule {}
