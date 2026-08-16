import { Controller, Get, Post, Body, Param, Req, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { NotificationsService } from './notifications.service';
import { CreateNotificationDto } from './dto/create-notification.dto';

@Controller('notifications')
@UseGuards(JwtAuthGuard, RolesGuard)
export class NotificationsController {
  constructor(private readonly service: NotificationsService) {}

  @Post()
  @Roles('administrateur', 'fabricant')
  envoyer(@Req() req: any, @Body() dto: CreateNotificationDto) {
    return this.service.envoyer(req.user.userId, dto);
  }

  @Post(':id/reponses')
  @Roles('point_de_vente')
  repondre(
    @Param('id') notificationId: string,
    @Body('pointDeVenteId') pointDeVenteId: string,
    @Body('optionChoisieId') optionChoisieId: string,
  ) {
    return this.service.repondreSondage(notificationId, pointDeVenteId, optionChoisieId);
  }

  @Get('point-de-vente')
  @Roles('point_de_vente')
  recuesParPointDeVente() {
    return this.service.findRecuesParPointDeVente();
  }
}
