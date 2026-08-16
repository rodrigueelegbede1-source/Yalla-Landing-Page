import { Controller, Get, Post, Patch, Body, Param, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { PointsDeVenteService } from './points-de-vente.service';
import { CreatePointDeVenteDto } from './dto/create-point-de-vente.dto';

@Controller('points-de-vente')
@UseGuards(JwtAuthGuard, RolesGuard)
export class PointsDeVenteController {
  constructor(private readonly service: PointsDeVenteService) {}

  // Enregistrement d'un nouveau point de vente — maquette Agent recenseur.
  @Post()
  @Roles('agent_recenseur', 'administrateur')
  create(@Body() dto: CreatePointDeVenteDto) {
    return this.service.create(dto);
  }

  @Get()
  @Roles('administrateur', 'fabricant', 'agent_recenseur')
  findAll(@Query('commune') commune?: string) {
    return this.service.findByCommune(commune);
  }

  @Get(':id')
  @Roles('administrateur', 'fabricant', 'agent_recenseur', 'point_de_vente')
  findOne(@Param('id') id: string) {
    return this.service.findOne(id);
  }

  // Validation d'un point de vente en attente — maquette Administrateur.
  @Patch(':id/activer')
  @Roles('administrateur')
  activer(@Param('id') id: string) {
    return this.service.activer(id);
  }

  @Patch(':id/retirer')
  @Roles('administrateur', 'point_de_vente')
  retirer(@Param('id') id: string) {
    return this.service.retirer(id);
  }
}
