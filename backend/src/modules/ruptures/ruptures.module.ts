import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Rupture } from '../../entities/rupture.entity';
import { RupturesService } from './ruptures.service';
import { RupturesController } from './ruptures.controller';
import { RealtimeGateway } from '../../gateways/realtime.gateway';

@Module({
  imports: [TypeOrmModule.forFeature([Rupture])],
  providers: [RupturesService, RealtimeGateway],
  controllers: [RupturesController],
  exports: [RupturesService],
})
export class RupturesModule {}
