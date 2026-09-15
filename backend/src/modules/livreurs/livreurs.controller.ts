import { Controller, Get, Post, Patch, Body, Param, Req, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { LivreursService } from './livreurs.service';
import { UpdatePositionDto } from './dto/update-position.dto';

@Controller('livreurs')
@UseGuards(JwtAuthGuard, RolesGuard)
export class LivreursController {
  constructor(private readonly service: LivreursService) {}

  // Appelé par l'app mobile du livreur à intervalle régulier (voir fréquence recommandée
  // dans Yalla_Stack_Technique.md). `req.user.userId` correspond au livreur authentifié.
  @Post('position')
  @Roles('livreur')
  enregistrerPosition(@Req() req: any, @Body() dto: UpdatePositionDto) {
    return this.service.enregistrerPosition(req.user.idMetier, dto.latitude, dto.longitude);
  }

  @Patch(':id/en-ligne')
  @Roles('livreur')
  setEnLigne(@Param('id') id: string, @Body('enLigne') enLigne: boolean) {
    return this.service.setEnLigne(id, enLigne);
  }

  @Get('fabricant/:fabricantId')
  @Roles('fabricant', 'administrateur')
  findByFabricant(@Param('fabricantId') fabricantId: string) {
    return this.service.findByFabricant(fabricantId);
  }

  // Flotte du distributeur connecté. Identifiant pris dans le token et non dans
  // l'URL : un distributeur n'a pas à consulter la flotte d'un concurrent.
  @Get('distributeur')
  @Roles('distributeur')
  findByDistributeur(@Req() req: any) {
    return this.service.findByDistributeur(req.user.idMetier);
  }
}
