import { Injectable } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ConfigService } from '@nestjs/config';
import { ExtractJwt, Strategy } from 'passport-jwt';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  // Le secret vient de ConfigService, exactement comme dans AuthModule. Lire
  // `process.env` des deux côtés paraissait équivalent, mais ne l'était pas :
  // les deux lectures n'avaient pas lieu au même moment du démarrage. Voir le
  // commentaire de auth.module.ts.
  constructor(config: ConfigService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: config.get<string>('JWT_SECRET') ?? 'change_me_en_production',
    });
  }

  async validate(payload: { sub: string; role: string; nom: string; idMetier: string | null }) {
    // Le payload signé devient `request.user`, consommé par RolesGuard et les contrôleurs.
    return { userId: payload.sub, role: payload.role, nom: payload.nom, idMetier: payload.idMetier };
  }
}
