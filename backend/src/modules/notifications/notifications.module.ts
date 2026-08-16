import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Notification, SondageOption, SondageReponse } from '../../entities/notification.entity';
import { NotificationsService } from './notifications.service';
import { NotificationsController } from './notifications.controller';
import { RealtimeGateway } from '../../gateways/realtime.gateway';

@Module({
  imports: [TypeOrmModule.forFeature([Notification, SondageOption, SondageReponse])],
  providers: [NotificationsService, RealtimeGateway],
  controllers: [NotificationsController],
})
export class NotificationsModule {}
