import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Rupture } from '../../entities/rupture.entity';
import { RealtimeGateway } from '../../gateways/realtime.gateway';

type ResultatEscalade = { rupture_id: string; action: 'escaladee' | 'perimee' };

/**
 * Fait vivre la règle d'escalade décidée le 2026-09-15.
 *
 * Passé `delai_escalade()` (2 h), une rupture que personne n'a prise s'ouvre aux
 * autres distributeurs qui portent le même fabricant dans la même commune.
 * Passé `delai_peremption()` (24 h), elle est close en `non_servie` et compte
 * comme un échec dans le taux de service.
 *
 * Le travail est fait en SQL par `escalader_ruptures_en_attente()` (migration
 * 011). Ce service ne fait que la déclencher à intervalle régulier et diffuser
 * le résultat aux clients connectés.
 *
 * Pourquoi un `setInterval` plutôt que `@nestjs/schedule` : le backend n'a pas
 * cette dépendance, et en ajouter une pour une seule tâche périodique ne se
 * justifie pas. La fonction SQL restant appelable à la main ou par pg_cron, on
 * pourra basculer sans rien réécrire le jour où plusieurs instances de l'API
 * tourneront en parallèle.
 */
@Injectable()
export class EscaladeService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(EscaladeService.name);
  private timer?: ReturnType<typeof setInterval>;

  // Une passe toutes les 5 minutes. Le délai d'escalade se compte en heures :
  // affiner davantage ne changerait rien pour le boutiquier et chargerait la base.
  private static readonly PERIODE_MS = 5 * 60 * 1000;

  constructor(
    @InjectRepository(Rupture) private readonly repo: Repository<Rupture>,
    private readonly realtime: RealtimeGateway,
  ) {}

  onModuleInit() {
    this.timer = setInterval(() => {
      // Volontairement non attendu : une passe en échec ne doit pas interrompre
      // le cycle, la suivante repassera sur les mêmes ruptures.
      this.executerPasse().catch((e) => this.logger.error(`Passe d'escalade en échec : ${e.message}`));
    }, EscaladeService.PERIODE_MS);

    // Ne maintient pas le processus en vie à lui seul (utile en test et en CLI).
    this.timer.unref?.();
  }

  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }

  /**
   * Une passe. Exposée publiquement pour l'endpoint d'administration, qui permet
   * de la déclencher en démonstration sans attendre le prochain tour d'horloge.
   */
  async executerPasse() {
    const resultats: ResultatEscalade[] = await this.repo.query(
      `SELECT rupture_id, action FROM escalader_ruptures_en_attente()`,
    );

    if (resultats.length === 0) return { escaladees: 0, perimees: 0 };

    const escaladees = resultats.filter((r) => r.action === 'escaladee');
    const perimees = resultats.filter((r) => r.action === 'perimee');

    // Une rupture qui s'ouvre au cercle élargi est une information utile à
    // l'instant où elle se produit : les distributeurs de la commune doivent la
    // voir apparaître sans rafraîchir leur écran.
    for (const r of escaladees) {
      const [ligne] = await this.repo.query(
        `SELECT p.fabricant_id AS "fabricantId" FROM ruptures r
         JOIN produits p ON p.id = r.produit_id WHERE r.id = $1`,
        [r.rupture_id],
      );
      // La vue d'accès donne exactement qui peut désormais prendre la course,
      // attribué et élargi confondus. On diffuse à ceux-là et à personne d'autre :
      // un distributeur de la commune qui ne travaille pas cette marque n'a rien
      // à recevoir.
      const acces = await this.repo.query(
        `SELECT distributeur_id AS "distributeurId"
         FROM v_acces_rupture_distributeur WHERE rupture_id = $1`,
        [r.rupture_id],
      );
      this.realtime.emettreActiviteReseau({
        type: 'rupture_escaladee',
        message: 'Rupture non prise, ouverte aux distributeurs de la commune',
        fabricantId: ligne?.fabricantId,
        distributeurIds: acces.map((a: { distributeurId: string }) => a.distributeurId),
      });
    }

    for (const r of perimees) {
      const [ligne] = await this.repo.query(
        `SELECT p.fabricant_id AS "fabricantId" FROM ruptures r
         JOIN produits p ON p.id = r.produit_id WHERE r.id = $1`,
        [r.rupture_id],
      );
      this.realtime.emettreActiviteReseau({
        type: 'rupture_non_servie',
        message: 'Rupture expirée sans avoir été servie',
        fabricantId: ligne?.fabricantId,
      });
    }

    this.logger.log(`Escalade : ${escaladees.length} ouverte(s) au cercle élargi, ${perimees.length} expirée(s)`);
    return { escaladees: escaladees.length, perimees: perimees.length };
  }
}
