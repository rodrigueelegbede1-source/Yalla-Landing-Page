import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Produit } from '../../entities/produit.entity';
import { ProduitsService } from './produits.service';
import { ProduitsController } from './produits.controller';

@Module({
  imports: [TypeOrmModule.forFeature([Produit])],
  providers: [ProduitsService],
  controllers: [ProduitsController],
  exports: [ProduitsService],
})
export class ProduitsModule {}
