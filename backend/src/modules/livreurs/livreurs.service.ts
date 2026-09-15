import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Livreur } from '../../entities/livreur.entity';
import { RealtimeGateway } from '../../gateways/realtime.gateway';

@Injectable()
export class LivreursService {
  constructor(
    @InjectRepository(Livreur) private readonly repo: Repository<Livreur>,
    private readonly realtime: RealtimeGateway,
  ) {}

  /**
   * Historise une position (table positions_livreurs) — le trigger SQL
   * `trg_positions_livreurs_sync` (migration 003) se charge de synchroniser
   * livreurs.position / position_maj_le automatiquement. On diffuse ensuite
   * l'événement en temps réel aux clients concernés.
   *
   * `livreurId` est désormais l'idMetier porté par le token JWT (voir
   * AuthService.resoudreIdMetier) — plus besoin de le résoudre ici à partir
   * de l'utilisateur à chaque appel.
   *
   * Fréquence attendue côté app mobile : ~10 s en course, ~60 s à l'arrêt,
   * rien lorsque le livreur est déconnecté (voir Yalla_Modele_de_donnees.md, §5).
   */
  async enregistrerPosition(livreurId: string, latitude: number, longitude: number) {
    const livreur = await this.repo.findOne({ where: { id: livreurId } });
    if (!livreur) throw new NotFoundException('Livreur introuvable');

    await this.repo.query(
      `INSERT INTO positions_livreurs (livreur_id, position, horodatage)
       VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography, now())`,
      [livreurId, longitude, latitude],
    );

    // Le livreur dépend d'un distributeur (migration 011). Sa position part à ce
    // distributeur, et au fabricant derrière lui quand il y en a un : un
    // distributeur indépendant ne rend de comptes à aucune marque en particulier.
    const [rattachement] = await this.repo.query(
      `SELECT d.id AS "distributeurId", d.fabricant_id AS "fabricantId"
       FROM distributeurs d WHERE d.id = $1`,
      [livreur.distributeurId],
    );

    this.realtime.emettrePositionLivreur(
      { distributeurId: rattachement?.distributeurId, fabricantId: rattachement?.fabricantId },
      { livreurId, latitude, longitude, horodatage: new Date() },
    );

    return { ok: true };
  }

  async setEnLigne(livreurId: string, enLigne: boolean) {
    await this.repo.update(livreurId, { enLigne });
    return { ok: true, enLigne };
  }

  /**
   * Les livreurs qu'un fabricant voit sur sa carte : ceux des distributeurs qui
   * lui sont rattachés, y compris son propre distributeur d'auto-distribution.
   *
   * Un fabricant ne voit donc pas les livreurs d'un distributeur indépendant,
   * même quand celui-ci sert ses produits. C'est cohérent avec le périmètre du
   * rôle (§6 d'AGENTS.md) : le fabricant voit son réseau, pas celui des autres.
   */
  async findByFabricant(fabricantId: string) {
    return this.repo.query(
      `SELECT l.id, u.nom, l.en_ligne AS "enLigne",
              d.id AS "distributeurId", d.nom AS "distributeurNom",
              ST_Y(l.position::geometry) AS latitude, ST_X(l.position::geometry) AS longitude,
              l.position_maj_le AS "positionMajLe"
       FROM livreurs l
       JOIN utilisateurs u ON u.id = l.utilisateur_id
       JOIN distributeurs d ON d.id = l.distributeur_id
       WHERE d.fabricant_id = $1
       ORDER BY d.nom, u.nom`,
      [fabricantId],
    );
  }

  /** Les livreurs d'un distributeur : sa propre flotte, sur son écran à lui. */
  async findByDistributeur(distributeurId: string) {
    return this.repo.query(
      `SELECT l.id, u.nom, l.en_ligne AS "enLigne",
              ST_Y(l.position::geometry) AS latitude, ST_X(l.position::geometry) AS longitude,
              l.position_maj_le AS "positionMajLe"
       FROM livreurs l
       JOIN utilisateurs u ON u.id = l.utilisateur_id
       WHERE l.distributeur_id = $1
       ORDER BY u.nom`,
      [distributeurId],
    );
  }
}
