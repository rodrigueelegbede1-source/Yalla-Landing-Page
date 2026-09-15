import { Injectable, UnauthorizedException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { Utilisateur } from '../../entities/utilisateur.entity';

@Injectable()
export class AuthService {
  constructor(
    @InjectRepository(Utilisateur) private readonly utilisateurs: Repository<Utilisateur>,
    private readonly jwtService: JwtService,
  ) {}

  async login(telephone: string, motDePasse: string) {
    const utilisateur = await this.utilisateurs.findOne({ where: { telephone } });
    if (!utilisateur) {
      throw new UnauthorizedException('Identifiants invalides');
    }

    const motDePasseValide = await bcrypt.compare(motDePasse, utilisateur.motDePasseHash);
    if (!motDePasseValide) {
      throw new UnauthorizedException('Identifiants invalides');
    }

    utilisateur.derniereConnexion = new Date();
    await this.utilisateurs.save(utilisateur);

    const idMetier = await this.resoudreIdMetier(utilisateur.id, utilisateur.role);

    const payload = { sub: utilisateur.id, role: utilisateur.role, nom: utilisateur.nom, idMetier };
    return {
      access_token: this.jwtService.sign(payload),
      utilisateur: {
        id: utilisateur.id,
        nom: utilisateur.nom,
        role: utilisateur.role,
        // ID de la table spécifique au rôle (fabricants.id, livreurs.id,
        // points_de_vente.id, agents_recenseurs.id) — absent pour un futur
        // rôle "point_de_vente" tant qu'il n'a pas son propre compte utilisateur
        // dédié (voir la limite déjà notée dans le README du backend).
        idMetier,
      },
    };
  }

  private async resoudreIdMetier(utilisateurId: string, role: string): Promise<string | null> {
    let table: string | null = null;
    switch (role) {
      case 'fabricant':
        table = 'fabricants';
        break;
      case 'livreur':
        table = 'livreurs';
        break;
      case 'distributeur':
        table = 'distributeurs';
        break;
      case 'agent_recenseur':
        table = 'agents_recenseurs';
        break;
      case 'point_de_vente':
        table = 'points_de_vente';
        break;
      default:
        // 'administrateur' n'a pas de table dédiée.
        return null;
    }
    const rows = await this.utilisateurs.query(
      `SELECT id FROM ${table} WHERE utilisateur_id = $1`,
      [utilisateurId],
    );
    return rows[0]?.id ?? null;
  }

  async hashMotDePasse(motDePasse: string): Promise<string> {
    return bcrypt.hash(motDePasse, 10);
  }
}
