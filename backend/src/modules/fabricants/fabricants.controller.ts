import { Controller, Get, Post, Param, Body, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { FabricantsService } from './fabricants.service';

@Controller('fabricants')
@UseGuards(JwtAuthGuard, RolesGuard)
export class FabricantsController {
  constructor(private readonly service: FabricantsService) {}

  @Get()
  @Roles('administrateur')
  findAll() {
    return this.service.findAll();
  }

  @Get(':id')
  @Roles('administrateur', 'fabricant')
  findOne(@Param('id') id: string) {
    return this.service.findOne(id);
  }

  @Get(':id/reseau')
  @Roles('fabricant', 'administrateur')
  reseau(@Param('id') id: string) {
    return this.service.findReseauAttribue(id);
  }

  @Get(':id/chiffre-affaires')
  @Roles('fabricant', 'administrateur')
  chiffreAffaires(@Param('id') id: string) {
    return this.service.chiffreAffaires(id);
  }

  // Attribution d'un point de vente à un fabricant — maquette Administrateur.
  @Post(':id/reseau/:pointDeVenteId')
  @Roles('administrateur')
  attribuer(@Param('id') id: string, @Param('pointDeVenteId') pointDeVenteId: string) {
    return this.service.attribuerPointDeVente(id, pointDeVenteId);
  }
}
