import { ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Rupture } from '../../entities/rupture.entity';
import { RealtimeGateway } from '../../gateways/realtime.gateway';

@Injectable()
export class RupturesService {
  constructor(
    @InjectRepository(Rupture) private readonly repo: Repository<Rupture>,
    private readonly realtime: RealtimeGateway,
  ) {}

  // Signalement manuel depuis l'app Point de vente (bouton "Signaler une rupture").
  // Le signalement automatique (vente qui vide un stock) passe par le trigger SQL
  // décrit dans 006_caisse_enregistreuse.sql, pas par ce endpoint.
  //
  // Le destinataire n'est PAS résolu ici : le trigger BEFORE INSERT de la
  // migration 011 s'en charge, pour que les deux chemins de création aboutissent
  // au même routage. On relit simplement la ligne pour savoir à qui diffuser.
  async signalerManuellement(pointDeVenteId: string, produitId: string, quantiteDemandee?: number) {
    const rupture = this.repo.create({
      pointDeVenteId,
      produitId,
      quantiteDemandee,
      statut: 'signalee',
      signalementAutomatique: false,
    });
    const saved = await this.repo.save(rupture);

    const [ligne] = await this.repo.query(
      `SELECT r.distributeur_id AS "distributeurId", p.fabricant_id AS "fabricantId"
       FROM ruptures r JOIN produits p ON p.id = r.produit_id
       WHERE r.id = $1`,
      [saved.id],
    );

    this.realtime.emettreActiviteReseau({
      type: 'rupture',
      message: 'Nouvelle rupture signalée',
      fabricantId: ligne?.fabricantId,
      distributeurId: ligne?.distributeurId,
    });

    return { ...saved, distributeurId: ligne?.distributeurId ?? null };
  }

  // Interface Fabricant : ruptures ouvertes sur son propre catalogue uniquement.
  // Lecture seule depuis la migration 011, c'est le distributeur qui agit.
  async findOuvertesParFabricant(fabricantId: string) {
    return this.repo.query(
      `SELECT * FROM v_ruptures_ouvertes WHERE fabricant_id = $1 ORDER BY date_signalement DESC`,
      [fabricantId],
    );
  }

  // Vue Administrateur : toutes les ruptures ouvertes du réseau.
  async findToutesOuvertes() {
    return this.repo.query(`SELECT * FROM v_ruptures_ouvertes ORDER BY date_signalement DESC`);
  }

  /**
   * Interface Distributeur : ce qu'il a le droit de prendre, et à quel titre.
   *
   * `cercle` vaut 'attribue' quand la rupture lui revient de droit, 'elargi'
   * quand elle lui parvient par escalade passé le délai. L'application affiche
   * les deux différemment : la seconde est une opportunité, pas une obligation.
   */
  async findPourDistributeur(distributeurId: string) {
    return this.repo.query(
      `SELECT ro.*, acc.cercle
       FROM v_ruptures_ouvertes ro
       JOIN v_acces_rupture_distributeur acc ON acc.rupture_id = ro.rupture_id
       WHERE acc.distributeur_id = $1
       ORDER BY acc.cercle, ro.date_signalement DESC`,
      [distributeurId],
    );
  }

  /**
   * Coeur de la maquette Livreur : les ruptures qu'il peut servir, triées par
   * proximité réelle (PostGIS) et non par un calcul de distance applicatif.
   *
   * Le périmètre passe désormais par le distributeur dont dépend le livreur, et
   * non plus par un fabricant : c'est la vue d'accès qui décide, escalade
   * comprise. Un livreur voit donc apparaître les ruptures du cercle élargi dès
   * que son distributeur y a droit.
   */
  async findProchesDuLivreur(livreurId: string, limite = 20) {
    return this.repo.query(
      `SELECT ro.*, acc.cercle, ST_Distance(ro.position, l.position) AS distance_metres
       FROM v_ruptures_ouvertes ro
       JOIN v_acces_rupture_distributeur acc ON acc.rupture_id = ro.rupture_id
       JOIN livreurs l ON l.id = $1 AND l.distributeur_id = acc.distributeur_id
       ORDER BY ro.position <-> l.position
       LIMIT $2`,
      [livreurId, limite],
    );
  }

  /**
   * Prise en charge par un livreur.
   *
   * L'UPDATE est conditionnel et atomique : le premier livreur qui arrive gagne,
   * les suivants ne touchent aucune ligne. L'ancienne version écrasait le statut
   * sans condition et sans enregistrer personne, si bien que deux livreurs
   * pouvaient partir sur la même course en croyant chacun l'avoir obtenue.
   *
   * La clause EXISTS vérifie du même mouvement que la rupture est dans le
   * périmètre du livreur, cercle élargi compris. Un livreur ne peut donc pas
   * prendre la course d'un autre distributeur en devinant un identifiant.
   */
  async prendreEnCharge(id: string, livreurId: string) {
    const resultat = await this.repo.query(
      `UPDATE ruptures r
       SET statut = 'prise_en_charge',
           livreur_id = l.id,
           date_prise_en_charge = now()
       FROM livreurs l
       WHERE r.id = $1
         AND l.id = $2
         AND r.statut = 'signalee'
         AND EXISTS (
           SELECT 1 FROM v_acces_rupture_distributeur acc
           WHERE acc.rupture_id = r.id
             AND acc.distributeur_id = l.distributeur_id
         )
       RETURNING r.id, r.statut, r.livreur_id AS "livreurId",
                 r.date_prise_en_charge AS "datePriseEnCharge"`,
      [id, livreurId],
    );

    // Sur le pilote postgres, TypeORM renvoie `[lignes, nombreAffecté]` pour un
    // UPDATE ... RETURNING, et non les lignes directement. Tester `.length` sur
    // le résultat brut donnait donc toujours 2, jamais 0 : le perdant recevait
    // un 200 avec un tableau vide au lieu d'un 409. Bug invisible au typage,
    // trouvé en interrogeant l'API pour de bon. On normalise les deux formes.
    const lignes = Array.isArray(resultat?.[0]) ? resultat[0] : resultat;

    if (!lignes || lignes.length === 0) {
      // Zéro ligne modifiée recouvre trois situations très différentes. On relit
      // pour renvoyer au livreur un message qui lui serve à quelque chose.
      const rupture = await this.repo.findOne({ where: { id } });
      if (!rupture) throw new NotFoundException('Rupture introuvable');
      if (rupture.statut !== 'signalee') {
        throw new ConflictException('Cette rupture vient d’être prise par un autre livreur');
      }
      throw new ForbiddenException('Cette rupture ne relève pas de votre distributeur');
    }

    const [ligne] = await this.repo.query(
      `SELECT r.distributeur_id AS "distributeurId", p.fabricant_id AS "fabricantId"
       FROM ruptures r JOIN produits p ON p.id = r.produit_id
       WHERE r.id = $1`,
      [id],
    );

    this.realtime.emettreActiviteReseau({
      type: 'rupture_prise_en_charge',
      message: 'Rupture prise en charge par un livreur',
      fabricantId: ligne?.fabricantId,
      distributeurId: ligne?.distributeurId,
    });

    return lignes[0];
  }
}
