/* ═══════════════════════════════════════════════════════════
   YALLA — Tableau de bord du distributeur

   CE QUE LE WEB APPORTE QUE LE MOBILE N'A PAS : l'écran large.
   Sur un téléphone, le distributeur voit trois courses et navigue
   entre trois onglets. Au bureau, il voit tout son réseau d'un
   coup et affecte à la chaîne. Cette page est donc organisée pour
   le pilotage, pas pour la consultation.

   LE TEMPS RÉEL EST ICI UN RAFRAÎCHISSEMENT PÉRIODIQUE, pas un
   abonnement. L'application mobile s'abonne à la diffusion
   Postgres, ce qui suppose une connexion WebSocket tenue ouverte.
   Sur ce réseau, où environ un appel sur dix se coupe, une
   interrogation toutes les vingt-cinq secondes est plus robuste
   qu'une connexion permanente qui tombe sans le dire. L'écran
   affiche l'heure de la dernière mise à jour, pour qu'on sache
   toujours si ce qu'on lit est frais.
   ═══════════════════════════════════════════════════════════ */

const URL_BASE = window.YALLA_CONFIG?.url ?? '';
const CLE = window.YALLA_CONFIG?.cle ?? '';
const PERIODE_MS = 25000;

const jeton = sessionStorage.getItem('yalla.jeton');
const nom = sessionStorage.getItem('yalla.nom') || '';

if (!jeton) location.replace('rejoindre.html');

const titre = document.getElementById('titreDistributeur');
const sousTitre = document.getElementById('sousTitreDistributeur');
const message = document.getElementById('messageBord');
const chiffres = document.getElementById('chiffres');
const pouls = document.getElementById('pouls');
const dialogue = document.getElementById('dialogueAffectation');

let flotteConnue = [];

document.getElementById('boutonDeconnexion').addEventListener('click', () => {
  sessionStorage.clear();
  location.replace('rejoindre.html');
});

/* ── Outils ────────────────────────────────────────────────── */

function echapper(texte) {
  const d = document.createElement('div');
  d.textContent = texte ?? '';
  return d.innerHTML;
}

function nombre(valeur) {
  if (valeur === null || valeur === undefined) return '—';
  return String(valeur).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
}

/* Durée courte, dans la forme utilisée partout ailleurs dans le produit :
   « 1 h 44 », « 12 min », « 45 s ». */
function duree(secondes) {
  const s = Math.max(0, Math.round(secondes));
  if (s >= 3600) {
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    return m === 0 ? `${h} h` : `${h} h ${m}`;
  }
  if (s >= 60) return `${Math.floor(s / 60)} min`;
  return `${s} s`;
}

function informer(texte, ton) {
  message.textContent = texte;
  message.dataset.ton = ton;
  message.hidden = false;
}

async function interroger(chemin, options = {}) {
  const reponse = await fetch(`${URL_BASE}/rest/v1/${chemin}`, {
    ...options,
    headers: {
      apikey: CLE,
      Authorization: `Bearer ${jeton}`,
      'Content-Type': 'application/json',
      ...(options.headers ?? {}),
    },
  });

  if (reponse.status === 401 || reponse.status === 403) {
    sessionStorage.clear();
    location.replace('rejoindre.html');
    throw new Error('session');
  }
  if (!reponse.ok) {
    const corps = await reponse.json().catch(() => ({}));
    throw new Error(corps.message || `HTTP ${reponse.status}`);
  }
  return reponse.json();
}

/* ── Le carnet ─────────────────────────────────────────────── */

function rendreCarnet(courses) {
  const zone = document.getElementById('zoneCarnet');

  if (!courses.length) {
    zone.innerHTML =
      '<div class="bord-vide">Aucune course en attente. Vos boutiques sont '
      + 'servies.</div>';
    return;
  }

  const rangs = courses.map((c) => {
    const restant = Number(c.secondes_avant_escalade ?? 0);
    const elargie = c.cercle === 'elargi';
    const prise = c.statut === 'prise_en_charge';

    // Trois états, trois messages. « Délai dépassé » ne veut pas dire perdue :
    // la course est simplement visible par les confrères, et reste prenable.
    let etat;
    if (elargie) {
      etat = '<span class="pastille pastille--attente">Élargie</span>';
    } else if (restant <= 0) {
      etat = '<span class="pastille pastille--attente">Ouverte aux autres</span>';
    } else if (restant < 1800) {
      etat = `<span class="pastille pastille--attente">${duree(restant)} restantes</span>`;
    } else {
      etat = `<span class="pastille pastille--ok">${duree(restant)} restantes</span>`;
    }

    const action = prise
      ? '<span style="opacity:.6">Affectée</span>'
      : `<button type="button" class="bord-action" data-rupture="${echapper(c.rupture_id)}"
           data-produit="${echapper(c.produit_nom)}"
           data-boutique="${echapper(c.point_de_vente_nom)}">Affecter</button>`;

    return `<tr>
      <td>
        ${echapper(c.produit_nom)}
        <br><small style="opacity:.6">${echapper(c.fabricant_nom ?? '')}${
          c.quantite_demandee ? ` · ${c.quantite_demandee} carton(s)` : ''
        }</small>
      </td>
      <td>${echapper(c.point_de_vente_nom)}<br><small style="opacity:.6">${echapper(c.commune ?? '')}</small></td>
      <td class="num">${duree(Number(c.anciennete_secondes ?? 0))}</td>
      <td>${etat}</td>
      <td>${action}</td>
    </tr>`;
  });

  zone.innerHTML = `<div class="bord-tableau-boite"><table class="bord-tableau">
    <thead><tr>
      <th>Produit</th><th>Boutique</th><th>Depuis</th><th>Délai</th><th></th>
    </tr></thead>
    <tbody>${rangs.join('')}</tbody>
  </table></div>`;

  for (const bouton of zone.querySelectorAll('.bord-action')) {
    bouton.addEventListener('click', () => ouvrirAffectation(bouton.dataset));
  }
}

/* ── La flotte ─────────────────────────────────────────────── */

function etatLivreur(l) {
  if (l.actif !== true) return { texte: 'Écarté', classe: 'attente' };
  if (l.en_ligne !== true) return { texte: 'Hors ligne', classe: 'attente' };

  const maj = l.position_maj_le ? new Date(l.position_maj_le) : null;
  const minutes = maj ? (Date.now() - maj) / 60000 : Infinity;

  // Au-delà de cinq minutes sans position, le téléphone ne remonte plus rien.
  // C'est la différence entre un livreur suivi et une application endormie par
  // le système, et le distributeur doit pouvoir la faire.
  if (minutes > 5) return { texte: 'Position figée', classe: 'attente' };
  return { texte: 'En ligne', classe: 'ok' };
}

function rendreFlotte(flotte) {
  const zone = document.getElementById('zoneFlotte');
  flotteConnue = flotte;

  if (!flotte.length) {
    zone.innerHTML =
      '<div class="bord-vide">Aucun livreur. Sans livreur, vous voyez les '
      + 'ruptures mais ne pouvez les affecter à personne : ajoutez-en un depuis '
      + 'l’application, son compte se remet en main propre.</div>';
    return;
  }

  const rangs = flotte.map((l) => {
    const etat = etatLivreur(l);
    return `<tr>
      <td>${echapper(l.nom)}</td>
      <td class="num">${echapper(l.telephone ?? '')}</td>
      <td><span class="pastille pastille--${etat.classe}">${etat.texte}</span></td>
      <td class="num">${nombre(l.courses_en_cours ?? 0)}</td>
      <td class="num">${nombre(l.livraisons_terminees ?? 0)}</td>
      <td>
        <button type="button" class="bord-action bord-action--discret"
                data-livreur="${echapper(l.livreur_id)}"
                data-actif="${l.actif === true}"
                data-nom="${echapper(l.nom)}">${
                  l.actif === true ? 'Écarter' : 'Réintégrer'
                }</button>
      </td>
    </tr>`;
  });

  zone.innerHTML = `<div class="bord-tableau-boite"><table class="bord-tableau">
    <thead><tr>
      <th>Livreur</th><th>Téléphone</th><th>État</th>
      <th>En cours</th><th>Livrées</th><th></th>
    </tr></thead>
    <tbody>${rangs.join('')}</tbody>
  </table></div>`;

  for (const bouton of zone.querySelectorAll('.bord-action')) {
    bouton.addEventListener('click', () => basculerLivreur(bouton.dataset));
  }
}

/* ── Le réseau ─────────────────────────────────────────────── */

function rendreReseau(boutiques) {
  const zone = document.getElementById('zoneReseau');

  if (!boutiques.length) {
    zone.innerHTML =
      '<div class="bord-vide">Aucune boutique déclarée. Tant que vous n’en '
      + 'déclarez aucune, les ruptures ne vous parviennent qu’après deux heures '
      + 'd’escalade, et en concurrence avec les autres distributeurs.</div>';
    return;
  }

  // Groupées par commune : c'est ainsi qu'un distributeur pense son secteur,
  // pas par ordre alphabétique de boutique.
  const communes = new Map();
  for (const b of boutiques) {
    const cle = b.commune || '—';
    if (!communes.has(cle)) communes.set(cle, []);
    communes.get(cle).push(b);
  }

  const blocs = [...communes.entries()].map(([commune, liste]) => {
    const rangs = liste.map((b) => `<tr>
      <td>${echapper(b.point_de_vente_nom)}</td>
      <td>${echapper(b.fabricant_nom)}</td>
      <td>${Number(b.ruptures_ouvertes ?? 0) > 0
        ? `<span class="pastille pastille--attente">${b.ruptures_ouvertes} ouverte(s)</span>`
        : '<span style="opacity:.5">—</span>'}</td>
    </tr>`);

    return `<h3 class="bord-commune">${echapper(commune)}
        <span>${liste.length} boutique(s)</span></h3>
      <div class="bord-tableau-boite"><table class="bord-tableau">
        <thead><tr><th>Boutique</th><th>Marque</th><th>Ruptures</th></tr></thead>
        <tbody>${rangs.join('')}</tbody>
      </table></div>`;
  });

  zone.innerHTML = blocs.join('');
}

/* ── Affecter ──────────────────────────────────────────────── */

function ouvrirAffectation({ rupture, produit, boutique }) {
  document.getElementById('sousTitreAffectation').textContent =
    `${produit} · ${boutique}`;

  const actifs = flotteConnue.filter((l) => l.actif === true);
  const liste = document.getElementById('listeLivreurs');

  if (!actifs.length) {
    liste.innerHTML =
      '<p class="bord-vide" style="margin:0">Aucun livreur actif dans votre '
      + 'flotte.</p>';
    dialogue.showModal();
    return;
  }

  // Les disponibles d'abord : un livreur en ligne sans course prendra la
  // sienne tout de suite, et c'est le seul critère qui compte à cet instant.
  const ordonnes = [...actifs].sort((a, b) => {
    const score = (l) => (l.en_ligne === true ? 0 : 2)
      + (Number(l.courses_en_cours ?? 0) > 0 ? 1 : 0);
    return score(a) - score(b);
  });

  liste.innerHTML = ordonnes.map((l) => {
    const etat = etatLivreur(l);
    const enCours = Number(l.courses_en_cours ?? 0);
    const detail = l.en_ligne === true
      ? (enCours > 0 ? `${etat.texte} · ${enCours} course(s) en cours` : `${etat.texte}, disponible`)
      : 'Hors ligne, il ne verra la course qu’à sa reconnexion';

    return `<button type="button" class="bord-livreur" data-livreur="${echapper(l.livreur_id)}"
              data-rupture="${echapper(rupture)}">
      <strong>${echapper(l.nom)}</strong>
      <em>${detail}</em>
    </button>`;
  }).join('');

  for (const bouton of liste.querySelectorAll('.bord-livreur')) {
    bouton.addEventListener('click', async () => {
      dialogue.close();
      await affecter(bouton.dataset.rupture, bouton.dataset.livreur);
    });
  }

  dialogue.showModal();
}

async function affecter(ruptureId, livreurId) {
  try {
    await interroger('rpc/affecter_livreur', {
      method: 'POST',
      body: JSON.stringify({ p_rupture_id: ruptureId, p_livreur_id: livreurId }),
    });
    informer('Course affectée.', 'succes');
    await rafraichir();
  } catch (erreur) {
    if (erreur.message === 'session') return;
    // Les messages de la base sont déjà rédigés pour être lus : « Course
    // indisponible : déjà prise, inexistante, ou hors de votre périmètre ».
    informer(erreur.message, 'erreur');
    await rafraichir();
  }
}

async function basculerLivreur({ livreur, actif, nom: nomLivreur }) {
  const ecarter = actif === 'true';

  if (ecarter && !confirm(
    `Écarter ${nomLivreur} ?\n\n`
    + 'Il ne recevra plus de course et n’apparaîtra plus sur votre carte. '
    + 'Son historique est conservé, et vous pouvez le réintégrer à tout moment.',
  )) return;

  try {
    await interroger('rpc/ecarter_livreur', {
      method: 'POST',
      body: JSON.stringify({ p_livreur_id: livreur, p_actif: !ecarter }),
    });
    await rafraichir();
  } catch (erreur) {
    if (erreur.message === 'session') return;
    informer(erreur.message, 'erreur');
  }
}

/* ── Chargement ────────────────────────────────────────────── */

function rendreChiffres(carnet, flotte, boutiques) {
  const aAffecter = carnet.filter((c) => c.statut !== 'prise_en_charge');
  const urgentes = aAffecter.filter((c) => {
    const r = Number(c.secondes_avant_escalade ?? 0);
    return r > 0 && r < 1800;
  });

  const actifs = flotte.filter((l) => l.actif === true);
  const enLigne = actifs.filter((l) => etatLivreur(l).texte === 'En ligne');

  const marques = new Set(boutiques.map((b) => b.fabricant_nom));
  const pdv = new Set(boutiques.map((b) => b.point_de_vente_id));

  document.getElementById('chiffreAttente').textContent = nombre(aAffecter.length);
  document.getElementById('detailAttente').textContent = aAffecter.length
    ? 'À affecter à un livreur.'
    : 'Rien en attente : vos boutiques sont servies.';

  document.getElementById('chiffreUrgent').textContent = nombre(urgentes.length);
  document.getElementById('chiffreFlotte').textContent = nombre(enLigne.length);
  document.getElementById('detailFlotte').textContent =
    `${nombre(actifs.length)} livreur(s) actif(s) dans la flotte.`;

  document.getElementById('chiffreBoutiques').textContent = nombre(pdv.size);
  document.getElementById('detailBoutiques').textContent =
    `${nombre(marques.size)} marque(s) portée(s).`;

  chiffres.hidden = false;
}

async function rafraichir() {
  try {
    const [carnet, flotte, reseau] = await Promise.all([
      interroger('v_carnet_distributeur?select=*&order=cercle,date_signalement.desc'),
      interroger('v_ma_flotte?select=*&order=actif.desc,en_ligne.desc,nom'),
      interroger('v_mon_reseau?select=*&order=commune,point_de_vente_nom'),
    ]);

    titre.textContent = nom || 'Mon réseau';
    sousTitre.textContent = 'Tableau de bord distributeur';

    rendreChiffres(carnet, flotte, reseau);
    rendreCarnet(carnet);
    rendreFlotte(flotte);
    rendreReseau(reseau);

    const heure = new Date().toLocaleTimeString('fr-FR', {
      hour: '2-digit',
      minute: '2-digit',
    });
    pouls.textContent = `à jour ${heure}`;
    pouls.dataset.etat = 'ok';
    message.hidden = true;
  } catch (erreur) {
    if (erreur.message === 'session') return;
    pouls.dataset.etat = 'perdu';
    informer(
      'Les données n’ont pas pu être rafraîchies. Sur ce réseau, un appel sur '
      + 'dix se coupe : la prochaine tentative part dans vingt-cinq secondes.',
      'erreur',
    );
  }
}

if (jeton) {
  rafraichir();

  // On suspend le rafraîchissement quand l'onglet passe en arrière-plan :
  // inutile d'interroger la base pour une page que personne ne regarde.
  let minuteur = setInterval(rafraichir, PERIODE_MS);
  document.addEventListener('visibilitychange', () => {
    clearInterval(minuteur);
    if (!document.hidden) {
      rafraichir();
      minuteur = setInterval(rafraichir, PERIODE_MS);
    }
  });
}
