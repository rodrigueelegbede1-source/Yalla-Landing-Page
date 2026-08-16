import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Fabricant } from '../../entities/fabricant.entity';
import { FabricantsService } from './fabricants.service';
import { FabricantsController } from './fabricants.controller';

@Module({
  imports: [TypeOrmModule.forFeature([Fabricant])],
  providers: [FabricantsService],
  controllers: [FabricantsController],
  exports: [FabricantsService],
})
export class FabricantsModule {}
