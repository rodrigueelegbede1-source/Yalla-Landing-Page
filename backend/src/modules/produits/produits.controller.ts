import { Controller, Get, Post, Delete, Param, Body, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { ProduitsService } from './produits.service';
import { CreateProduitDto } from './dto/create-produit.dto';

@Controller('produits')
@UseGuards(JwtAuthGuard, RolesGuard)
export class ProduitsController {
  constructor(private readonly service: ProduitsService) {}

  @Get('fabricant/:fabricantId')
  @Roles('fabricant', 'administrateur')
  parFabricant(@Param('fabricantId') fabricantId: string) {
    return this.service.findParFabricant(fabricantId);
  }

  @Get('catalogue-global')
  @Roles('point_de_vente', 'administrateur', 'livreur')
  catalogueGlobal(@Query('categorieId') categorieId?: string) {
    return this.service.findCatalogueGlobal(categorieId);
  }

  @Post('fabricant/:fabricantId')
  @Roles('fabricant')
  ajouter(@Param('fabricantId') fabricantId: string, @Body() dto: CreateProduitDto) {
    return this.service.ajouter(fabricantId, dto);
  }

  @Delete(':id')
  @Roles('fabricant')
  retirer(@Param('id') id: string) {
    return this.service.retirer(id);
  }
}
