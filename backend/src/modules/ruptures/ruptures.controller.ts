import { Controller, Get, Post, Patch, Body, Param, Query, Req, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { RupturesService } from './ruptures.service';
import { EscaladeService } from './escalade.service';
import { SignalerRuptureDto } from './dto/signaler-rupture.dto';

@Controller('ruptures')
@UseGuards(JwtAuthGuard, RolesGuard)
export class RupturesController {
  constructor(
    private readonly service: RupturesService,
    private readonly escalade: EscaladeService,
  ) {}

  @Post('point-de-vente/:pointDeVenteId')
  @Roles('point_de_vente')
  signaler(@Param('pointDeVenteId') pointDeVenteId: string, @Body() dto: SignalerRuptureDto) {
    return this.service.signalerManuellement(pointDeVenteId, dto.produitId, dto.quantiteDemandee);
  }

  // Lecture seule : depuis la migration 011, c'est le distributeur qui prend la
  // course. Le fabricant voit son marché, il n'agit pas dessus.
  @Get('fabricant/:fabricantId')
  @Roles('fabricant', 'administrateur')
  findParFabricant(@Param('fabricantId') fabricantId: string) {
    return this.service.findOuvertesParFabricant(fabricantId);
  }

  // Interface Distributeur. L'identifiant vient du token et non de l'URL : un
  // distributeur ne consulte que son propre carnet de courses.
  @Get('distributeur')
  @Roles('distributeur')
  findPourDistributeur(@Req() req: any) {
    return this.service.findPourDistributeur(req.user.idMetier);
  }

  @Get()
  @Roles('administrateur')
  findToutes() {
    return this.service.findToutesOuvertes();
  }

  // Consommé par la maquette Livreur (écran "Carte" + liste "à proximité").
  // `idMetier` du token plutôt qu'un paramètre d'URL, pour la même raison que
  // ci-dessous : l'identifiant d'un autre livreur se devine trop facilement.
  @Get('proximite')
  @Roles('livreur')
  findProches(@Req() req: any, @Query('limite') limite?: string) {
    return this.service.findProchesDuLivreur(req.user.idMetier, limite ? parseInt(limite, 10) : undefined);
  }

  // Le livreur est lu dans le token, jamais dans le corps ni dans l'URL : sans
  // cela, n'importe quel livreur pourrait s'attribuer la course d'un autre.
  @Patch(':id/prendre-en-charge')
  @Roles('livreur')
  prendreEnCharge(@Param('id') id: string, @Req() req: any) {
    return this.service.prendreEnCharge(id, req.user.idMetier);
  }

  // Déclenche une passe d'escalade sans attendre le cycle de 5 minutes. Utile en
  // démonstration, et pour rejouer la règle après un arrêt prolongé de l'API.
  @Post('escalade/passe')
  @Roles('administrateur')
  declencherEscalade() {
    return this.escalade.executerPasse();
  }
}
