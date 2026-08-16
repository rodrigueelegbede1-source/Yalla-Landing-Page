import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Livraison } from '../../entities/livraison.entity';
import { LivraisonsService } from './livraisons.service';
import { LivraisonsController } from './livraisons.controller';

@Module({
  imports: [TypeOrmModule.forFeature([Livraison])],
  providers: [LivraisonsService],
  controllers: [LivraisonsController],
  exports: [LivraisonsService],
})
export class LivraisonsModule {}
