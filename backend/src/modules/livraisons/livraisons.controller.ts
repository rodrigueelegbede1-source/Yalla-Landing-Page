import { Controller, Get, Post, Patch, Param, Body, Req, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { LivraisonsService } from './livraisons.service';
import { CreateLivraisonDto } from './dto/create-livraison.dto';

@Controller('livraisons')
@UseGuards(JwtAuthGuard, RolesGuard)
export class LivraisonsController {
  constructor(private readonly service: LivraisonsService) {}

  @Post()
  @Roles('livreur')
  demarrer(@Req() req: any, @Body() dto: CreateLivraisonDto) {
    return this.service.demarrer(req.user.idMetier, dto);
  }

  @Patch(':id/terminer')
  @Roles('livreur')
  terminer(@Param('id') id: string, @Body('montant') montant?: number) {
    return this.service.terminer(id, montant);
  }

  @Patch(':id/annuler')
  @Roles('livreur')
  annuler(@Param('id') id: string) {
    return this.service.annuler(id);
  }

  @Get('livreur/:livreurId')
  @Roles('livreur', 'fabricant', 'administrateur')
  parLivreur(@Param('livreurId') livreurId: string) {
    return this.service.findParLivreur(livreurId);
  }
}
