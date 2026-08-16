import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { CaisseService } from './caisse.service';
import { CreateVenteDto } from './dto/create-vente.dto';

@Controller('caisse')
@UseGuards(JwtAuthGuard, RolesGuard)
export class CaisseController {
  constructor(private readonly service: CaisseService) {}

  @Post('ventes')
  @Roles('point_de_vente')
  enregistrerVente(@Body() dto: CreateVenteDto) {
    return this.service.enregistrerVente(dto);
  }

  @Get('stock/:pointDeVenteId')
  @Roles('point_de_vente', 'administrateur')
  stock(@Param('pointDeVenteId') pointDeVenteId: string) {
    return this.service.stockDuPointDeVente(pointDeVenteId);
  }
}
