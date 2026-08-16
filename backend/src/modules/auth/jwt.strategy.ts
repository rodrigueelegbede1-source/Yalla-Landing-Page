import { Injectable } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor() {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: process.env.JWT_SECRET ?? 'change_me_en_production',
    });
  }

  async validate(payload: { sub: string; role: string; nom: string; idMetier: string | null }) {
    // Le payload signé devient `request.user`, consommé par RolesGuard et les contrôleurs.
    return { userId: payload.sub, role: payload.role, nom: payload.nom, idMetier: payload.idMetier };
  }
}
