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
const nomDistributeur = sessionStorage.getItem('yalla.nom') || 'Distributeur';

if (!jeton) location.replace('rejoindre.html');

const VERT = '#146B3A';
const JAUNE = '#FFE500';
const ALERTE = '#D65C52';

const message = document.getElementById('messageBord');
const chiffres = document.getElementById('chiffres');
const pouls = document.getElementById('pouls');
const dialogue = document.getElementById('dialogueAffectation');

let flotteConnue = [];
let etat = { carnet: [], flotte: [], reseau: [], activite: [] };
let filtreCommuneTableau = '';

document.getElementById('boutonDeconnexion').addEventListener('click', () => {
  sessionStorage.clear();
  location.replace('rejoindre.html');
});

/* ══ Navigation ═══════════════════════════════════════════ */

const VOLETS = {
  tableau: 'voletTableau',
  operations: 'voletOperations',
};

function ouvrirVolet(nom) {
  for (const [cle, id] of Object.entries(VOLETS)) {
    document.getElementById(id).hidden = cle !== nom;
  }
  for (const onglet of document.querySelectorAll('.console-onglet')) {
    onglet.classList.toggle('est-actif', onglet.dataset.volet === nom);
  }
  history.replaceState(null, '', `#${nom}`);
}

for (const onglet of document.querySelectorAll('.console-onglet')) {
  onglet.addEventListener('click', () => ouvrirVolet(onglet.dataset.volet));
}

for (const bouton of document.querySelectorAll('.periods button')) {
  bouton.addEventListener('click', () => {
    for (const b of document.querySelectorAll('.periods button')) b.classList.remove('selected');
    bouton.classList.add('selected');
  });
}

const selectCommuneTableau = document.getElementById('filtreCommuneTableau');
if (selectCommuneTableau) {
  selectCommuneTableau.addEventListener('change', (e) => {
    filtreCommuneTableau = e.target.value;
    tracerCouverture();
  });
}

/* ── Outils ────────────────────────────────────────────────── */

function echapper(texte) {
  const d = document.createElement('div');
  d.textContent = texte ?? '';
  return d.innerHTML;
}

function nombre(valeur) {
  if (valeur === null || valeur === undefined) return '—';
  return String(valeur).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
}

function montant(valeur) {
  const v = Number(valeur ?? 0);
  if (!Number.isFinite(v)) return '—';
  if (v >= 1000000) return `${(v / 1000000).toFixed(1).replace('.', ',')} M`;
  if (v >= 10000) return `${Math.round(v / 1000)} k`;
  return nombre(Math.round(v));
}

/* Durée courte, dans la forme utilisée partout ailleurs dans le produit :
   « 1 h 44 », « 12 min », « 45 s ». */
function duree(secondes) {
  const s = Math.max(0, Math.round(Number(secondes ?? 0)));
  if (s >= 86400) return `${Math.floor(s / 86400)} j`;
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
      '<div class="bord-vide">Aucune demande à livrer. Vos revendeurs sont '
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
      ? '<span style="opacity:.6">En livraison</span>'
      : `<button type="button" class="bord-action" data-rupture="${echapper(c.rupture_id)}"
           data-produit="${echapper(c.produit_nom)}"
           data-boutique="${echapper(c.point_de_vente_nom)}">Assigner</button>`;

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
      <th>Produit</th><th>Revendeur</th><th>Depuis</th><th>Délai</th><th></th>
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
      + 'demandes mais ne pouvez les affecter à personne : ajoutez-en un depuis '
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
      <th>Demandes en livraison</th><th>Livrées</th><th></th>
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
      '<div class="bord-vide">Aucun revendeur déclaré. Tant que vous n’en '
      + 'déclarez aucun, les demandes ne vous parviennent qu’après deux heures '
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
        ? `<span class="pastille pastille--attente">${b.ruptures_ouvertes} demande(s) ouverte(s)</span>`
        : '<span style="opacity:.5">—</span>'}</td>
    </tr>`);

    return `<h3 class="bord-commune">${echapper(commune)}
        <span>${liste.length} revendeur(s)</span></h3>
      <div class="bord-tableau-boite"><table class="bord-tableau">
        <thead><tr><th>Revendeur</th><th>Marque</th><th>Demandes</th></tr></thead>
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
      ? (enCours > 0 ? `${etat.texte} · ${enCours} livraison(s) en cours` : `${etat.texte}, disponible`)
      : 'Hors ligne, il ne verra la demande qu’à sa reconnexion';

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
    informer('Livreur assigné à la demande.', 'succes');
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
    + 'Il ne recevra plus de demande à livrer et n’apparaîtra plus sur votre carte. '
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

/* ══ Mon réseau ═══════════════════════════════════════════ */

function remplirCommunes() {
  const communes = [...new Set(etat.reseau.map((b) => b.commune).filter(Boolean))].sort();
  const options = communes.map((c) => `<option value="${echapper(c)}">${echapper(c)}</option>`).join('');
  const select = document.getElementById('filtreCommuneTableau');
  if (!select) return;
  const choix = select.value;
  select.innerHTML = `<option value="">Toutes les communes</option>${options}`;
  select.value = communes.includes(choix) ? choix : '';
}

function tracerReseauChiffres() {
  const { carnet, flotte, reseau } = etat;
  const aAffecter = carnet.filter((c) => c.statut !== 'prise_en_charge');
  const actifs = flotte.filter((l) => l.actif === true);
  const enLigne = actifs.filter((l) => etatLivreur(l).texte === 'En ligne');
  const marques = new Set(reseau.map((b) => b.fabricant_nom));
  const pdv = new Set(reseau.map((b) => b.point_de_vente_id));

  const optionEspace = document.getElementById('optionEspaceDistributeur');
  if (optionEspace) optionEspace.textContent = `Distributeur · ${nomDistributeur}`;

  document.getElementById('chiffreATraiter').textContent = nombre(aAffecter.length);
  document.getElementById('detailATraiter').textContent = aAffecter.length
    ? 'À affecter à un livreur.'
    : 'Rien en attente : vos revendeurs sont servis.';

  document.getElementById('chiffrePdv').textContent = nombre(pdv.size);
  document.getElementById('detailPdv').textContent = `${nombre(marques.size)} marque(s) représentée(s)`;

  document.getElementById('chiffreMarques').textContent = nombre(marques.size);
  document.getElementById('detailMarques').textContent = `Sur ${nombre(pdv.size)} revendeur(s)`;

  document.getElementById('chiffreLivreurs').textContent = nombre(enLigne.length);
  document.getElementById('detailLivreurs').textContent =
    `${nombre(actifs.length)} livreur(s) actif(s) dans la flotte`;

  const jours = etat.activite;
  const aujourdhui = jours.length ? jours[jours.length - 1] : null;
  const livraisonsAuj = Number(aujourdhui?.livraisons ?? 0);
  document.getElementById('chiffreLivraisons').textContent = nombre(livraisonsAuj);
  document.getElementById('detailLivraisons').textContent = 'Vos propres livreurs, aujourd’hui';

  document.getElementById('tableChiffres').innerHTML = [
    ['Revendeurs desservis', pdv.size, ''],
    ['Marques distribuées', marques.size, ''],
    ['Livreurs dans la flotte', flotte.length, `${nombre(actifs.length)} actif(s)`],
    ['Demandes en cours', aAffecter.length, ''],
  ].map(([nom2, v, detail]) => `
    <div class="network-stat">
      <strong>${nombre(v)}</strong>
      <span>${echapper(nom2)}${detail ? ` · ${echapper(detail)}` : ''}</span>
    </div>`).join('');
}

/* ── Le rythme, sur ce que le distributeur peut légitimement voir : les
   demandes visibles dans son périmètre (partagées entre confrères par les
   politiques de la base) et ses propres livraisons confirmées, qui restent
   strictement les siennes. ─────────────────────────────────────────────── */
function tracerActivite() {
  const boite = document.getElementById('grapheActivite');
  const pied = document.getElementById('piedActivite');
  const jours = etat.activite;

  if (!jours.length) {
    boite.innerHTML = '<div class="vide" style="border:0;padding:20px 0">Pas encore de données.</div>';
    pied.textContent = '';
    return;
  }

  const L = 720;
  const H = 210;
  const margeG = 34;
  const margeD = 10;
  const margeH = 16;
  const margeB = 34;
  const larg = L - margeG - margeD;
  const haut = H - margeH - margeB;

  const maxi = Math.max(1, ...jours.map((j) => Math.max(Number(j.signalees), Number(j.livraisons))));
  const plafond = Math.max(2, Math.ceil(maxi / 2) * 2);
  const pas = larg / jours.length;
  const y = (v) => margeH + haut - (v / plafond) * haut;

  const grilles = [0, plafond / 2, plafond].map((v) =>
    `<line x1="${margeG}" y1="${y(v).toFixed(1)}" x2="${L - margeD}" y2="${y(v).toFixed(1)}" class="graphe-grille"/>`
    + `<text x="${margeG - 7}" y="${(y(v) + 3.5).toFixed(1)}" text-anchor="end" class="graphe-axe">${v}</text>`).join('');

  const barres = jours.map((j, i) => {
    const v = Number(j.signalees);
    const hauteur = (v / plafond) * haut;
    const x = margeG + i * pas + pas * 0.22;
    const l = pas * 0.56;
    return `<rect x="${x.toFixed(1)}" y="${y(v).toFixed(1)}" width="${l.toFixed(1)}"
      height="${Math.max(0, hauteur).toFixed(1)}" rx="2" fill="${ALERTE}" opacity=".85"/>`;
  }).join('');

  const points = jours.map((j, i) =>
    `${(margeG + i * pas + pas / 2).toFixed(1)},${y(Number(j.livraisons)).toFixed(1)}`);

  const ligne = `<polyline points="${points.join(' ')}" fill="none" stroke="${VERT}"
    stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/>`
    + jours.map((j, i) =>
      `<circle cx="${(margeG + i * pas + pas / 2).toFixed(1)}" cy="${y(Number(j.livraisons)).toFixed(1)}" r="3.2" fill="${VERT}"/>`).join('');

  const etiquettes = jours.map((j, i) => {
    if (i % Math.ceil(jours.length / 8) !== 0 && i !== jours.length - 1) return '';
    const d = new Date(j.jour);
    const texte = `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}`;
    return `<text x="${(margeG + i * pas + pas / 2).toFixed(1)}" y="${H - 8}" text-anchor="middle" class="graphe-axe">${texte}</text>`;
  }).join('');

  boite.innerHTML = `
    <svg viewBox="0 0 ${L} ${H}" role="img" aria-label="Demandes et livraisons sur quatorze jours">
      ${grilles}${barres}${ligne}${etiquettes}
    </svg>
    <div class="legende" style="flex-direction:row;gap:18px;margin-top:4px">
      <div style="flex:0"><i style="background:${ALERTE}"></i>Demandes visibles</div>
      <div style="flex:0"><i style="background:${VERT}"></i>Vos livraisons</div>
    </div>`;

  const aujourdhui = jours[jours.length - 1];
  const total14 = jours.reduce((s, j) => s + Number(j.livraisons), 0);
  pied.textContent = total14 === 0
    ? 'Aucune de vos livraisons n’a bougé sur ces quatorze jours.'
    : `${nombre(aujourdhui.livraisons)} livraison(s) confirmée(s) aujourd’hui par vos livreurs, sur ${nombre(total14)} ces quatorze derniers jours.`;
}

/* ── Couverture : la part de vos revendeurs avec une demande ouverte en ce
   moment, et la répartition de ces demandes par commune. ────────────────── */
function tracerCouverture() {
  const anneau = document.getElementById('anneauCouverture');
  const valeur = document.getElementById('valeurCouverture');
  const copie = document.getElementById('texteCouverture');
  const barres = document.getElementById('communesCouverture');
  const pied = document.getElementById('piedCouverture');

  const reseau = etat.reseau;
  const total = reseau.length;
  const enAttente = reseau.filter((b) => Number(b.ruptures_ouvertes ?? 0) > 0).length;
  const part = total === 0 ? 0 : Math.min(100, Math.round((enAttente / total) * 100));

  anneau.style.background = `conic-gradient(${ALERTE} 0 ${part}%, #e6ebe5 ${part}% 100%)`;
  valeur.textContent = `${part} %`;
  copie.innerHTML = `<strong>${nombre(enAttente)} revendeur(s) en attente</strong>`
    + `<p>Sur ${nombre(total)} revendeur(s) que vous desservez.</p>`;

  const demandes = etat.carnet.filter((c) => c.statut !== 'prise_en_charge'
    && (!filtreCommuneTableau || c.commune === filtreCommuneTableau));
  const parCommune = new Map();
  for (const c of demandes) {
    const cle = c.commune || '—';
    parCommune.set(cle, (parCommune.get(cle) ?? 0) + 1);
  }
  const totalDemandes = demandes.length;
  const rangs = [...parCommune.entries()]
    .map(([commune, n]) => ({ commune, n, taux: totalDemandes === 0 ? 0 : Math.round((n / totalDemandes) * 100) }))
    .sort((a, b) => b.n - a.n)
    .slice(0, 6);

  barres.innerHTML = !rangs.length
    ? '<div class="vide" style="border:0;padding:8px 0">Aucune demande en cours sur votre réseau.</div>'
    : rangs.map((r) => `<div class="commune-row">
        <span>${echapper(r.commune)}</span>
        <div class="track"><i style="width:${r.taux}%"></i></div>
        <b>${nombre(r.n)}</b>
      </div>`).join('');

  pied.textContent = total === 0
    ? 'Aucun revendeur déclaré pour l’instant.'
    : enAttente === 0
      ? 'Aucun de vos revendeurs n’a de demande ouverte pour l’instant.'
      : `${nombre(enAttente)} revendeur(s) sur ${nombre(total)} attendent une livraison.`;
}

/* ── Les demandes en cours, les plus en attente d'abord ──────────────── */
function tracerDemandesEnCours() {
  const boite = document.getElementById('demandesEnCoursListe');
  const pied = document.getElementById('piedRuptures');

  const enCours = etat.carnet.filter((c) => c.statut !== 'prise_en_charge');
  const total = enCours.length;

  if (!total) {
    boite.innerHTML = '<div class="vide" style="border:0;padding:12px 0">'
      + 'Aucune demande en cours. Vos revendeurs sont servis.</div>';
  } else {
    const ordonnees = [...enCours]
      .sort((a, b) => Number(b.anciennete_secondes ?? 0) - Number(a.anciennete_secondes ?? 0))
      .slice(0, 6);

    boite.innerHTML = ordonnees.map((c) => {
      const attente = Number(c.anciennete_secondes ?? 0);
      const progression = Math.min(100, Math.round((attente / 7200) * 100));
      const elargie = c.cercle === 'elargi';
      return `<div class="signal-item">
        <div class="signal-heading">
          <strong>${echapper(c.produit_nom)} · ${echapper(c.point_de_vente_nom)}</strong>
          <span class="status">${elargie ? 'Élargie' : 'En attente'}</span>
        </div>
        <div class="signal-meta"><span>${echapper(c.commune ?? '')}${
          c.fabricant_nom ? ` · ${echapper(c.fabricant_nom)}` : ''}</span><span>${duree(attente)}</span></div>
        <div class="signal-meter"><i style="width:${progression}%"></i></div>
      </div>`;
    }).join('');
  }

  const urgentes = enCours.filter((c) => {
    const r = Number(c.secondes_avant_escalade ?? 0);
    return r > 0 && r < 1800;
  }).length;
  pied.textContent = total === 0
    ? 'Aucune demande en cours.'
    : urgentes > 0
      ? `${urgentes} demande(s) vont s’ouvrir aux autres distributeurs sous trente minutes.`
      : 'Aucune demande n’est à moins de trente minutes de l’escalade.';
}

/* ── Prévision et valeur des livraisons, sur vos seules livraisons ───── */
function tracerPrevision() {
  const boite = document.getElementById('previsionListe');
  const jours = etat.activite;
  const aujourdhui = jours.length ? jours[jours.length - 1] : null;
  const duJour = Number(aujourdhui?.montant ?? 0);
  const livraisons = Number(aujourdhui?.livraisons ?? 0);
  const panier = livraisons > 0 ? duJour / livraisons : null;
  const maxi = Math.max(duJour, 1);

  boite.innerHTML = `
    <div class="finance-item">
      <div class="finance-label"><span>Livré confirmé aujourd’hui (estimation logistique)</span><strong>${montant(duJour)}</strong></div>
      <div class="finance-track"><i style="width:${Math.round((duJour / maxi) * 100)}%"></i></div>
    </div>
    <div class="finance-item${panier === null ? ' finance-item--untracked' : ''}">
      <div class="finance-label"><span>Panier moyen par livraison</span><strong>${
        panier === null ? '—' : montant(Math.round(panier))}</strong></div>
      ${panier === null ? '<small>Aucune livraison confirmée aujourd’hui.</small>'
        : `<div class="finance-track"><i style="width:${Math.min(100, Math.round((panier / maxi) * 100))}%"></i></div>`}
    </div>
    <div class="finance-item finance-item--untracked">
      <div class="finance-label"><span>CA prévisionnel (non clôturé)</span><strong>Non calculable</strong></div>
      <small>Les demandes en cours n'ont pas de montant tant qu'elles ne sont pas livrées.</small>
    </div>
    <div class="finance-item finance-item--untracked">
      <div class="finance-label"><span>Pipeline pondéré</span><strong>Non suivi</strong></div>
      <small>Aucun suivi commercial des prospects dans l'application.</small>
    </div>`;
}

/* ── Les métriques honnêtes : ce qui se calcule vraiment ─────────────── */
function tracerMetriques() {
  const enAttente = etat.carnet.filter((c) => c.statut !== 'prise_en_charge');
  const metricAnciennete = document.getElementById('metricAnciennete');
  if (!enAttente.length) {
    metricAnciennete.textContent = '—';
  } else {
    const moyenne = enAttente.reduce((s, c) => s + Number(c.anciennete_secondes ?? 0), 0) / enAttente.length;
    metricAnciennete.textContent = duree(moyenne);
  }

  const courses = etat.flotte.reduce((s, l) => s + Number(l.courses_en_cours ?? 0), 0);
  document.getElementById('metricCourses').textContent = nombre(courses);
}

/* ── Demandes récentes, les plus récentes d'abord ────────────────────── */
function tracerDemandesRecentes() {
  const boite = document.getElementById('demandesRecentesListe');

  if (!etat.carnet.length) {
    boite.innerHTML = '<div class="vide" style="border:0;padding:12px 0">'
      + 'Aucune demande reçue sur votre périmètre à ce jour.</div>';
    return;
  }

  const ordonnees = [...etat.carnet]
    .sort((a, b) => Number(a.anciennete_secondes ?? 0) - Number(b.anciennete_secondes ?? 0))
    .slice(0, 8);

  boite.innerHTML = ordonnees.map((c) => {
    const attente = Number(c.anciennete_secondes ?? 0);
    const pris = c.statut === 'prise_en_charge';
    const point = pris ? 'route' : '';
    const libelle = pris ? 'Prise en charge' : c.cercle === 'elargi' ? 'Élargie' : 'En attente';
    return `<div class="event-item">
      <span class="event-dot ${point}"></span>
      <div class="event-main">
        <strong>${echapper(c.produit_nom)} · ${echapper(c.point_de_vente_nom)}</strong>
        <span>${echapper(c.commune ?? '')}${c.fabricant_nom ? ` · ${echapper(c.fabricant_nom)}` : ''}</span>
      </div>
      <div class="event-value">${duree(attente)}<small>${libelle}</small></div>
    </div>`;
  }).join('');
}

/* ── Les livreurs les plus actifs, sur l'historique complet de la flotte ─ */
function tracerLivreursActifs() {
  const boite = document.getElementById('livreursActifsListe');
  const classes = [...etat.flotte]
    .filter((l) => Number(l.livraisons_terminees ?? 0) > 0)
    .sort((a, b) => Number(b.livraisons_terminees) - Number(a.livraisons_terminees))
    .slice(0, 6);

  if (!classes.length) {
    boite.innerHTML = '<div class="vide" style="border:0;padding:12px 0;color:#a9b9ae">'
      + 'Non suivi : aucun de vos livreurs n’a encore terminé de livraison.</div>';
    return;
  }

  const maxi = Math.max(1, ...classes.map((l) => Number(l.livraisons_terminees)));
  boite.innerHTML = classes.map((l) => `<div class="rank-item">
    <div class="rank-heading"><strong>${echapper(l.nom)}</strong><span>${nombre(l.livraisons_terminees)}</span></div>
    <div class="rank-meter"><i style="width:${Math.round((Number(l.livraisons_terminees) / maxi) * 100)}%"></i></div>
    <div class="rank-sub">Livraisons terminées, historique complet</div>
  </div>`).join('');
}

/* ── Les revendeurs avec le plus de demandes ouvertes ─────────────────── */
function tracerRevendeursApercu() {
  const boite = document.getElementById('revendeursApercuListe');

  const ordonnes = [...etat.reseau]
    .filter((b) => Number(b.ruptures_ouvertes ?? 0) > 0)
    .sort((a, b) => Number(b.ruptures_ouvertes) - Number(a.ruptures_ouvertes))
    .slice(0, 6);

  if (!ordonnes.length) {
    boite.innerHTML = '<div class="vide" style="border:0;padding:12px 0;color:#a9b9ae">'
      + 'Aucune demande ouverte à ce jour.</div>';
    return;
  }

  const maxi = Math.max(1, ...ordonnes.map((b) => Number(b.ruptures_ouvertes)));

  boite.innerHTML = ordonnes.map((b, i) => {
    const n = Number(b.ruptures_ouvertes);
    return `<div class="product-row">
      <span class="product-rank">${i + 1}</span>
      <span class="product-name">${echapper(b.point_de_vente_nom)}<br><small style="opacity:.75">${echapper(b.commune ?? '')}</small></span>
      <div class="product-bar"><i style="width:${Math.round((n / maxi) * 100)}%"></i></div>
      <span class="product-count">${nombre(n)} demande(s)</span>
    </div>`;
  }).join('');
}

/* ── Vos marques distribuées, par nombre de revendeurs rattachés ─────── */
function tracerMarquesApercu() {
  const boite = document.getElementById('marquesApercuListe');

  const parMarque = new Map();
  for (const b of etat.reseau) {
    const cle = b.fabricant_nom || '—';
    if (!parMarque.has(cle)) parMarque.set(cle, new Set());
    parMarque.get(cle).add(b.point_de_vente_id);
  }
  const classes = [...parMarque.entries()]
    .map(([nom2, pdv]) => ({ nom: nom2, n: pdv.size }))
    .sort((a, b) => b.n - a.n)
    .slice(0, 6);

  if (!classes.length) {
    boite.innerHTML = '<div class="vide" style="border:0;padding:12px 0">Aucune marque déclarée.</div>';
    return;
  }

  const maxi = Math.max(1, ...classes.map((m) => m.n));
  boite.innerHTML = classes.map((m) => `<div class="rank-item">
    <div class="rank-heading"><strong>${echapper(m.nom)}</strong><span>${nombre(m.n)}</span></div>
    <div class="rank-meter"><i style="width:${Math.round((m.n / maxi) * 100)}%"></i></div>
    <div class="rank-sub">Revendeur(s) rattaché(s)</div>
  </div>`).join('');
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
    : 'Rien en attente : vos revendeurs sont servis.';

  document.getElementById('chiffreUrgent').textContent = nombre(urgentes.length);
  document.getElementById('chiffreFlotte').textContent = nombre(enLigne.length);
  document.getElementById('detailFlotte').textContent =
    `${nombre(actifs.length)} livreur(s) actif(s) dans la flotte.`;

  document.getElementById('chiffreBoutiques').textContent = nombre(pdv.size);
  document.getElementById('detailBoutiques').textContent =
    `${nombre(marques.size)} marque(s) · ${nombre(pdv.size)} revendeur(s).`;

  chiffres.hidden = false;
}

async function rafraichir() {
  try {
    const [carnet, flotte, reseau, activite] = await Promise.all([
      interroger('v_carnet_distributeur?select=*&order=cercle,date_signalement.desc'),
      interroger('v_ma_flotte?select=*&order=actif.desc,en_ligne.desc,nom'),
      interroger('v_mon_reseau?select=*&order=commune,point_de_vente_nom'),
      interroger('v_supervision_activite?select=*&order=jour'),
    ]);

    etat = { carnet, flotte, reseau, activite };

    document.getElementById('nomDistributeur').textContent = nomDistributeur;
    document.getElementById('initiales').textContent = nomDistributeur
      .split(/\s+/).filter(Boolean).slice(0, 2).map((m) => m[0].toUpperCase()).join('') || 'D';

    const aAffecter = carnet.filter((c) => c.statut !== 'prise_en_charge');
    const badge = document.getElementById('compteurOperations');
    if (badge) {
      badge.textContent = aAffecter.length;
      badge.hidden = aAffecter.length === 0;
    }

    rendreChiffres(carnet, flotte, reseau);
    rendreCarnet(carnet);
    rendreFlotte(flotte);
    rendreReseau(reseau);

    remplirCommunes();
    tracerReseauChiffres();
    tracerActivite();
    tracerCouverture();
    tracerDemandesEnCours();
    tracerPrevision();
    tracerMetriques();
    tracerDemandesRecentes();
    tracerLivreursActifs();
    tracerRevendeursApercu();
    tracerMarquesApercu();

    const heure = new Date().toLocaleTimeString('fr-FR', {
      hour: '2-digit',
      minute: '2-digit',
    });
    pouls.textContent = `à jour ${heure}`;
    pouls.dataset.etat = 'ok';
    const pouls2 = document.getElementById('pouls2');
    if (pouls2) { pouls2.textContent = heure; pouls2.dataset.etat = 'ok'; }
    message.hidden = true;
  } catch (erreur) {
    if (erreur.message === 'session') return;
    pouls.dataset.etat = 'perdu';
    const pouls2 = document.getElementById('pouls2');
    if (pouls2) pouls2.dataset.etat = 'perdu';
    informer(
      'Les données n’ont pas pu être rafraîchies. Sur ce réseau, un appel sur '
      + 'dix se coupe : la prochaine tentative part dans vingt-cinq secondes.',
      'erreur',
    );
  }
}

if (jeton) {
  if (VOLETS[location.hash.slice(1)]) ouvrirVolet(location.hash.slice(1));

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
