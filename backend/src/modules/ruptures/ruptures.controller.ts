import { Controller, Get, Post, Patch, Body, Param, Query, Req, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { RupturesService } from './ruptures.service';
import { SignalerRuptureDto } from './dto/signaler-rupture.dto';

@Controller('ruptures')
@UseGuards(JwtAuthGuard, RolesGuard)
export class RupturesController {
  constructor(private readonly service: RupturesService) {}

  @Post('point-de-vente/:pointDeVenteId')
  @Roles('point_de_vente')
  signaler(@Param('pointDeVenteId') pointDeVenteId: string, @Body() dto: SignalerRuptureDto) {
    return this.service.signalerManuellement(pointDeVenteId, dto.produitId, dto.quantiteDemandee);
  }

  @Get('fabricant/:fabricantId')
  @Roles('fabricant', 'administrateur')
  findParFabricant(@Param('fabricantId') fabricantId: string) {
    return this.service.findOuvertesParFabricant(fabricantId);
  }

  @Get()
  @Roles('administrateur')
  findToutes() {
    return this.service.findToutesOuvertes();
  }

  // Consommé par la maquette Livreur (écran "Carte" + liste "à proximité").
  @Get('proximite/:livreurId')
  @Roles('livreur')
  findProches(@Param('livreurId') livreurId: string, @Query('limite') limite?: string) {
    return this.service.findProchesDuLivreur(livreurId, limite ? parseInt(limite, 10) : undefined);
  }

  @Patch(':id/prendre-en-charge')
  @Roles('livreur')
  prendreEnCharge(@Param('id') id: string) {
    return this.service.prendreEnCharge(id);
  }
}
