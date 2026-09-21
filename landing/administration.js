/* ═══════════════════════════════════════════════════════════
   YALLA — Console de supervision du réseau

   L'écran de l'administrateur, en deux moitiés qui se relaient.

   LA GRILLE ANALYTIQUE répond à « comment va le réseau ».
   Jauge du taux de service, anneau des ruptures, couverture,
   rythme sur quatorze jours. On la balaye, on repère l'écart.

   LA CONSOLE D'EXPLOITATION répond à « que dois-je faire
   maintenant ». Rail cherchable à gauche, carte du terrain à
   droite, tiroir de détail en dessous. On cherche une entité,
   on la regarde, on agit sur elle.

   Un administrateur ouvre la page pour la première question et
   la referme sur la seconde.

   ── SES DEUX GESTES UTILES, ET CE QU'ILS DÉBLOQUENT ────────

     1. VALIDER UNE DEMANDE. Sans lui, les inscriptions déposées
        depuis le site s'empilent dans une table que personne ne
        regarde, et le demandeur attend un appel qui ne vient pas.
     2. ATTRIBUER UNE BOUTIQUE. Un distributeur qui démarre ne
        voit rien : sa politique ne lui montre que les communes
        où il opère déjà, et il n'en a aucune. Sa première
        boutique doit lui venir de l'extérieur.

   ── CE QUE CET ÉCRAN NE MONTRE PAS ────────────────────────

   Les ventes et le chiffre d'affaires d'une boutique. La
   promesse faite au boutiquier est que sa caisse n'appartient
   qu'à lui, et une promesse qui souffre une exception pour
   l'exploitant n'en est plus une. Les politiques de la base
   refusent ces lignes à ce compte : la page n'a rien à cacher,
   elle n'y a simplement pas accès.

   ── AUCUNE BIBLIOTHÈQUE EXTÉRIEURE ────────────────────────

   Jauge, anneau, courbes et carte sont dessinés ici, en SVG.
   Charger une bibliothèque de graphiques ou un fond de carte
   obligerait à élargir `script-src` et `img-src` dans la
   politique de sécurité du site, qui s'applique à toutes ses
   pages. Quelques fonctions de tracé coûtent moins cher qu'une
   brèche ouverte pour tout le monde.

   ── LE TEMPS RÉEL EST UN RAFRAÎCHISSEMENT PÉRIODIQUE ──────

   Pas un abonnement. Sur ce réseau, où environ un appel sur dix
   se coupe, une interrogation toutes les trente secondes est
   plus robuste qu'une connexion permanente qui tombe sans le
   dire. L'écran affiche l'heure de la dernière lecture, pour
   qu'on sache toujours si ce qu'on lit est frais.
   ═══════════════════════════════════════════════════════════ */

const URL_BASE = window.YALLA_CONFIG?.url ?? '';
const CLE = window.YALLA_CONFIG?.cle ?? '';
const PERIODE_MS = 30000;

const jeton = sessionStorage.getItem('yalla.jeton');
const nomAdmin = sessionStorage.getItem('yalla.nom') || 'Administrateur';

if (!jeton) location.replace('rejoindre.html');

/* Les couleurs sont reprises des jetons de styles.css. Elles sont répétées ici
   parce qu'un attribut SVG `fill` ne lit pas une variable CSS de façon fiable
   dans tous les navigateurs, et qu'un graphique à moitié coloré est pire
   qu'un graphique monochrome. */
const VERT = '#229453';
const VERT_VIF = '#3ED598';
const VERT_SOMBRE = '#0E4A2C';
const JAUNE = '#E8CF00';
const ALERTE = '#FF5C39';

const message = document.getElementById('message');
const pouls = document.getElementById('pouls');

const fValidation = document.getElementById('fenetreValidation');
const fAttribution = document.getElementById('fenetreAttribution');
const fIdentifiants = document.getElementById('fenetreIdentifiants');

/* Ce que la dernière lecture a rendu. Gardé pour remplir les fenêtres et le
   tiroir sans réinterroger la base au moment du clic. */
let etat = {
  reseau: {},
  demandes: [],
  anomalies: [],
  distributeurs: [],
  boutiques: [],
  marques: [],
  activite: [],
};

let railActif = 'boutiques';
let filtreRail = '';
let selection = null;          // { type, id }
let demandeEnCours = null;
let distributeurEnCours = null;

/* ══ Outils ═══════════════════════════════════════════════ */

function echapper(texte) {
  const d = document.createElement('div');
  d.textContent = texte ?? '';
  return d.innerHTML;
}

function nombre(valeur) {
  if (valeur === null || valeur === undefined) return '—';
  return String(valeur).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
}

/* Ancienneté en clair. Une demande déposée il y a trois jours et une déposée
   ce matin n'appellent pas la même urgence, et « 2026-09-18 » ne le dit pas. */
function anciennete(secondes) {
  const s = Math.max(0, Math.round(Number(secondes ?? 0)));
  if (s >= 172800) return `il y a ${Math.floor(s / 86400)} jours`;
  if (s >= 86400) return 'hier';
  if (s >= 7200) return `il y a ${Math.floor(s / 3600)} h`;
  if (s >= 120) return `il y a ${Math.floor(s / 60)} min`;
  return 'à l’instant';
}

/* Le numéro tel qu'on le lit à voix haute, pas tel qu'il est stocké. */
function telephoneLisible(brut) {
  const v = String(brut ?? '').replace(/[^0-9]/g, '');
  const national = v.startsWith('225') ? v.slice(3) : v;
  if (national.length !== 10) return brut ?? '';
  return national.replace(/(\d{2})(?=\d)/g, '$1 ').trim();
}

/* Mot de passe dicté de vive voix, jamais lu sur un écran par celui qui le
   tape. On retire donc tout ce qui s'entend pareil ou se lit de travers : ni l
   ni 1, ni O ni 0, ni I. Huit caractères, comme partout ailleurs. */
function motDePasseLisible() {
  const alphabet = 'ABCDEFGHJKMNPQRTUVWXYabcdefghijkmnpqrstuvwxy23456789';
  const tirage = new Uint32Array(8);
  crypto.getRandomValues(tirage);
  return [...tirage].map((n) => alphabet[n % alphabet.length]).join('');
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

/* ══ Navigation ═══════════════════════════════════════════ */

const VOLETS = {
  tableau: 'voletTableau',
  reseau: 'voletReseau',
  demandes: 'voletDemandes',
  anomalies: 'voletAnomalies',
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

document.getElementById('boutonDeconnexion').addEventListener('click', () => {
  sessionStorage.clear();
  location.replace('rejoindre.html');
});

/* ══ Tracés ═══════════════════════════════════════════════ */

/* Un point du cercle, en coordonnées SVG. L'angle est en degrés et part de
   l'ouest : 180 à gauche, 270 en haut, 360 à droite. */
function pointCercle(cx, cy, r, degres) {
  const a = (degres * Math.PI) / 180;
  return [cx + r * Math.cos(a), cy + r * Math.sin(a)];
}

function arc(cx, cy, r, de, a, epaisseur, couleur) {
  const [x1, y1] = pointCercle(cx, cy, r, de);
  const [x2, y2] = pointCercle(cx, cy, r, a);
  const grand = a - de > 180 ? 1 : 0;
  return `<path d="M ${x1.toFixed(2)} ${y1.toFixed(2)} A ${r} ${r} 0 ${grand} 1 `
    + `${x2.toFixed(2)} ${y2.toFixed(2)}" fill="none" stroke="${couleur}" `
    + `stroke-width="${epaisseur}" stroke-linecap="butt"/>`;
}

/* ── La jauge du taux de service ──────────────────────────
   Trois bandes plutôt qu'un dégradé continu : le lecteur doit pouvoir dire
   « on est dans le rouge » sans lire le chiffre. Les seuils sont ceux qu'on
   défendra devant un fabricant, 50 et 80. */
function tracerJauge(valeur) {
  const boite = document.getElementById('jaugeService');
  const pied = document.getElementById('piedService');
  const closes = Number(etat.reseau.ruptures_closes ?? 0);

  if (valeur === null || valeur === undefined) {
    boite.innerHTML =
      '<svg viewBox="0 0 240 150" role="img" aria-label="Taux de service indisponible">'
      + arc(120, 120, 92, 180, 360, 20, '#EDEAE0')
      + '<text x="120" y="112" text-anchor="middle" class="jauge-valeur" '
      + 'style="fill:rgba(8,22,14,.35)">—</text></svg>';
    pied.textContent =
      'Aucune rupture close pour l’instant. L’indicateur attend le terrain : '
      + 'il se calcule sur les ruptures servies contre non servies.';
    return;
  }

  const v = Math.max(0, Math.min(100, Number(valeur)));
  const angle = 180 + (v / 100) * 180;
  const [ax, ay] = pointCercle(120, 120, 72, angle);
  const [bx, by] = pointCercle(120, 120, 10, angle + 90);
  const [cx2, cy2] = pointCercle(120, 120, 10, angle - 90);

  boite.innerHTML =
    `<svg viewBox="0 0 240 150" role="img" aria-label="Taux de service ${v} %">`
    + arc(120, 120, 92, 180, 270, 20, ALERTE)
    + arc(120, 120, 92, 270, 324, 20, JAUNE)
    + arc(120, 120, 92, 324, 360, 20, VERT)
    // L'aiguille est un triangle plein : une simple ligne se perd sur les
    // bandes colorées, qui sont épaisses.
    + `<path d="M ${ax.toFixed(2)} ${ay.toFixed(2)} L ${bx.toFixed(2)} ${by.toFixed(2)} `
    + `L ${cx2.toFixed(2)} ${cy2.toFixed(2)} Z" fill="#0A3D24"/>`
    + '<circle cx="120" cy="120" r="7" fill="#0A3D24"/>'
    + `<text x="120" y="104" text-anchor="middle" class="jauge-valeur">${v}</text>`
    + '<text x="120" y="120" text-anchor="middle" class="jauge-unite">POUR CENT</text>'
    + '<text x="26" y="142" class="jauge-borne">0</text>'
    + '<text x="214" y="142" text-anchor="end" class="jauge-borne">100</text>'
    + '</svg>';

  // Trois lectures pour un même chiffre. Le taux ne se commente pas tout seul :
  // 62 % se lit comme un bon résultat si l'on ne sait pas ce qu'on vend.
  const lecture = v >= 80 ? 'C’est le chiffre qui se défend devant un fabricant.'
    : v >= 50 ? 'Tenable, mais ce n’est pas encore un argument de vente.'
      : 'Sous cinquante, le produit ne tient pas sa promesse.';

  pied.innerHTML = 'Calculé sur <b style="font-family:var(--ff-mono);color:var(--ink)">'
    + `${nombre(closes)}</b> rupture(s) close(s). ${lecture}`;
}

/* ── L'anneau des ruptures ────────────────────────────────
   Trois états, et ils ne se corrigent pas au même endroit : à confirmer, c'est
   le boutiquier qui doit répondre ; ouverte, c'est le distributeur qui doit
   prendre ; prise en charge, c'est le livreur qui roule. */
function tracerAnneau() {
  const boite = document.getElementById('anneauRuptures');
  const pied = document.getElementById('piedRuptures');

  const parts = [
    { nom: 'À confirmer', valeur: Number(etat.reseau.ruptures_a_confirmer ?? 0), couleur: JAUNE,
      note: 'Le boutiquier n’a pas encore validé le signalement automatique.' },
    { nom: 'Ouvertes', valeur: Number(etat.reseau.ruptures_ouvertes ?? 0), couleur: ALERTE,
      note: 'Confirmées, en attente d’un distributeur.' },
    { nom: 'Prises en charge', valeur: Number(etat.reseau.ruptures_prises ?? 0), couleur: VERT,
      note: 'Un livreur est dessus.' },
  ];
  const total = parts.reduce((s, p) => s + p.valeur, 0);

  const r = 52;
  const circonference = 2 * Math.PI * r;
  let parcouru = 0;

  const segments = total === 0
    ? `<circle cx="66" cy="66" r="${r}" fill="none" stroke="#EDEAE0" stroke-width="20"/>`
    : parts.filter((p) => p.valeur > 0).map((p) => {
      const longueur = (p.valeur / total) * circonference;
      const decalage = -parcouru;
      parcouru += longueur;
      // Un liseré blanc de 2px sépare les segments : sans lui, deux couleurs
      // voisines de valeur proche se lisent comme une seule.
      return `<circle cx="66" cy="66" r="${r}" fill="none" stroke="${p.couleur}"
        stroke-width="20" stroke-dasharray="${Math.max(0, longueur - 2).toFixed(2)} ${circonference.toFixed(2)}"
        stroke-dashoffset="${decalage.toFixed(2)}" transform="rotate(-90 66 66)"/>`;
    }).join('');

  boite.innerHTML = `
    <svg viewBox="0 0 132 132" role="img" aria-label="${total} rupture(s) en cours">
      ${segments}
      <text x="66" y="66" text-anchor="middle" class="anneau-total">${total}</text>
      <text x="66" y="82" text-anchor="middle" class="anneau-legende">EN COURS</text>
    </svg>
    <div class="legende">
      ${parts.map((p) => `<div>
        <i style="background:${p.couleur}"></i>${echapper(p.nom)}<b>${nombre(p.valeur)}</b>
      </div>`).join('')}
    </div>`;

  const bloquant = parts[0].valeur;
  pied.textContent = total === 0
    ? 'Aucune rupture en cours. Toutes les boutiques du réseau sont servies.'
    : bloquant > 0
      ? `${bloquant} attend${bloquant > 1 ? 'ent' : ''} la confirmation du boutiquier : `
        + 'tant qu’il n’a pas répondu, aucun distributeur ne les voit.'
      : 'Toutes les ruptures en cours sont confirmées et visibles des distributeurs.';
}

/* ── La couverture du réseau ──────────────────────────────
   Le seuil à 100 % n'est pas décoratif : une boutique sans distributeur
   produit des ruptures sans destinataire, qui n'existent qu'après deux heures
   d'escalade. C'est la seule barre de cet écran dont l'objectif est absolu. */
function tracerCouverture() {
  const boite = document.getElementById('objectifCouverture');
  const pied = document.getElementById('piedCouverture');

  const actives = etat.boutiques.filter((b) => b.statut === 'actif');
  const desservies = actives.filter((b) => b.distributeurs);
  const total = actives.length;
  const part = total === 0 ? 0 : Math.round((desservies.length / total) * 100);

  boite.innerHTML = `
    <div class="objectif-piste">
      <div class="objectif-remplissage" style="width:${part}%"></div>
      <div class="objectif-seuil" style="inset-inline-start:calc(100% - 2px)" data-libelle="Objectif"></div>
    </div>
    <div class="objectif-bornes">
      <span>${nombre(desservies.length)} desservie(s)</span>
      <span>${part} %</span>
      <span>${nombre(total)} active(s)</span>
    </div>`;

  const orphelines = total - desservies.length;
  pied.textContent = total === 0
    ? 'Aucune boutique active. Le recensement se fait sur le terrain, depuis l’application.'
    : orphelines === 0
      ? 'Chaque boutique active a son distributeur. C’est l’état normal du réseau.'
      : `${orphelines} boutique(s) que personne ne dessert : leurs ruptures `
        + 'n’apparaîtront qu’après deux heures d’escalade, et pour tout le monde à la fois.';
}

/* ── Le rythme du réseau ──────────────────────────────────
   Barres pour les signalements, ligne pour les résolutions. Une courbe de
   signalements seule ne dit rien : c'est l'écart entre les deux qui raconte si
   le réseau absorbe ce qu'il reçoit. */
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

  const maxi = Math.max(1, ...jours.map((j) => Math.max(Number(j.signalees), Number(j.resolues))));
  // Un plafond arrondi vers le haut donne des lignes de grille lisibles
  // (0, 2, 4 plutôt que 0, 1.66, 3.33).
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
    `${(margeG + i * pas + pas / 2).toFixed(1)},${y(Number(j.resolues)).toFixed(1)}`);

  const ligne = `<polyline points="${points.join(' ')}" fill="none" stroke="${VERT}"
    stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/>`
    + jours.map((j, i) =>
      `<circle cx="${(margeG + i * pas + pas / 2).toFixed(1)}" cy="${y(Number(j.resolues)).toFixed(1)}"
        r="3" fill="#FFFFFF" stroke="${VERT}" stroke-width="2"/>`).join('');

  // Une date sur deux : quatorze étiquettes se chevauchent sur un écran
  // étroit, et la lecture se fait de toute façon par la forme, pas au jour près.
  const dates = jours.map((j, i) => {
    if (i % 2 !== 0 && i !== jours.length - 1) return '';
    const d = new Date(`${j.jour}T00:00:00`);
    const texte = `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}`;
    return `<text x="${(margeG + i * pas + pas / 2).toFixed(1)}" y="${H - 14}"
      text-anchor="middle" class="graphe-axe">${texte}</text>`;
  }).join('');

  boite.innerHTML = `
    <svg viewBox="0 0 ${L} ${H}" role="img"
         aria-label="Ruptures signalées et résolues sur quatorze jours">
      ${grilles}${barres}${ligne}${dates}
    </svg>
    <div class="legende" style="flex-direction:row;gap:18px;margin-top:10px">
      <div style="flex:0"><i style="background:${ALERTE}"></i>Signalées</div>
      <div style="flex:0"><i style="background:${VERT}"></i>Résolues</div>
    </div>`;

  const signalees = jours.reduce((s, j) => s + Number(j.signalees), 0);
  const resolues = jours.reduce((s, j) => s + Number(j.resolues), 0);
  pied.textContent = signalees === 0 && resolues === 0
    ? 'Rien n’a bougé sur ces quatorze jours. Le pilote n’a pas encore produit de rupture.'
    : `${nombre(signalees)} signalée(s) et ${nombre(resolues)} résolue(s) sur la période. `
      + (resolues >= signalees
        ? 'Le réseau absorbe ce qu’il reçoit.'
        : 'Le réseau reçoit plus qu’il ne résout : l’écart se creuse.');
}

/* ── Le réseau en chiffres ────────────────────────────────
   Une table plutôt que six cartes à gros chiffre : ce sont des grandeurs de
   nature différente, qu'on lit par comparaison et pas par saisissement. */
function tracerChiffres() {
  const r = etat.reseau;
  const lignes = [
    ['Boutiques actives', r.boutiques_actives, r.boutiques_total !== r.boutiques_actives
      ? `${nombre(r.boutiques_total)} recensée(s) au total` : ''],
    ['Distributeurs', r.distributeurs, ''],
    ['Livreurs en ligne', r.livreurs_en_ligne, `${nombre(r.livreurs_actifs)} actif(s) dans les flottes`],
    ['Marques', r.fabricants, `${nombre(r.produits)} référence(s) au catalogue`],
    ['Demandes en attente', r.demandes_en_attente, ''],
  ];

  document.getElementById('tableChiffres').innerHTML = `<tbody>${
    lignes.map(([nom, valeur, detail]) => `<tr>
      <td>${echapper(nom)}${detail ? `<small>${echapper(detail)}</small>` : ''}</td>
      <td class="num" style="font-size:16px;color:var(--green-800);font-weight:600">${nombre(valeur)}</td>
    </tr>`).join('')
  }</tbody>`;
}

/* ── Les boutiques par commune ────────────────────────────
   Barres horizontales empilées : le nom d'une commune ivoirienne est long, il
   se lit en ligne et pas à la verticale sous un histogramme. */
function tracerCommunes() {
  const boite = document.getElementById('grapheCommunes');
  const actives = etat.boutiques.filter((b) => b.statut === 'actif');

  if (!actives.length) {
    boite.innerHTML = '<div class="vide" style="border:0;padding:20px 0">Aucune boutique active.</div>';
    return;
  }

  const parCommune = new Map();
  for (const b of actives) {
    const cle = b.commune || '—';
    if (!parCommune.has(cle)) parCommune.set(cle, { desservies: 0, orphelines: 0 });
    parCommune.get(cle)[b.distributeurs ? 'desservies' : 'orphelines'] += 1;
  }

  const rangs = [...parCommune.entries()]
    .map(([commune, v]) => ({ commune, ...v, total: v.desservies + v.orphelines }))
    .sort((a, b) => b.total - a.total)
    .slice(0, 9);

  const maxi = Math.max(1, ...rangs.map((r) => r.total));
  const L = 560;
  const hauteurRang = 30;
  const margeG = 150;
  const larg = L - margeG - 44;
  const H = rangs.length * hauteurRang + 8;

  const corps = rangs.map((r, i) => {
    const yy = i * hauteurRang + 4;
    const lDesservies = (r.desservies / maxi) * larg;
    const lOrphelines = (r.orphelines / maxi) * larg;
    return `
      <text x="${margeG - 10}" y="${yy + 14}" text-anchor="end" class="graphe-etiquette">${echapper(r.commune)}</text>
      ${r.desservies ? `<rect x="${margeG}" y="${yy + 3}" width="${lDesservies.toFixed(1)}" height="17" rx="2.5" fill="${VERT}"/>` : ''}
      ${r.orphelines ? `<rect x="${(margeG + lDesservies).toFixed(1)}" y="${yy + 3}" width="${lOrphelines.toFixed(1)}" height="17" rx="2.5" fill="${ALERTE}"/>` : ''}
      <text x="${(margeG + lDesservies + lOrphelines + 8).toFixed(1)}" y="${yy + 16}" class="graphe-valeur">${r.total}</text>`;
  }).join('');

  boite.innerHTML = `
    <svg viewBox="0 0 ${L} ${H}" role="img" aria-label="Boutiques actives par commune">${corps}</svg>
    <div class="legende" style="flex-direction:row;gap:18px;margin-top:10px">
      <div style="flex:0"><i style="background:${VERT}"></i>Desservies</div>
      <div style="flex:0"><i style="background:${ALERTE}"></i>Sans distributeur</div>
    </div>`;
}

/* ── La charge des distributeurs ──────────────────────────
   La chaleur encode les courses en attente, et rien d'autre. Une cellule à
   zéro reste blanche : teinter le vide ferait croire à une quantité. */
function tracerCharge() {
  const table = document.getElementById('tableCharge');
  const liste = etat.distributeurs;

  if (!liste.length) {
    table.innerHTML = '<tbody><tr><td style="color:rgba(8,22,14,.5)">Aucun distributeur enregistré.</td></tr></tbody>';
    return;
  }

  const maxi = Math.max(1, ...liste.map((d) => Number(d.courses_en_attente ?? 0)));

  table.innerHTML = `
    <thead><tr>
      <th>Distributeur</th><th class="num">Boutiques</th>
      <th class="num">Livreurs</th><th class="num">En attente</th>
    </tr></thead>
    <tbody>${liste.map((d) => {
      const attente = Number(d.courses_en_attente ?? 0);
      const intensite = attente === 0 ? 0 : 0.14 + (attente / maxi) * 0.56;
      const livreurs = Number(d.livreurs ?? 0);
      return `<tr>
        <td>${echapper(d.nom)}<small>${d.fabricant_rattache
          ? `Affilié · ${echapper(d.fabricant_rattache)}` : 'Indépendant'}</small></td>
        <td class="num">${nombre(d.boutiques ?? 0)}</td>
        <td class="num" ${livreurs === 0 ? 'style="color:#9B3218"' : ''}>${nombre(livreurs)}</td>
        <td class="num"><span class="cellule-chaude"
          style="background:rgba(255,92,57,${intensite.toFixed(2)})">${nombre(attente)}</span></td>
      </tr>`;
    }).join('')}</tbody>`;
}

/* ══ Le rail ══════════════════════════════════════════════ */

/* L'état d'une boutique, dans l'ordre où il compte. Sans distributeur passe
   avant sans stock : une boutique que personne ne dessert est un problème de
   réseau, une boutique sans stock est un problème de démarrage. */
function etatBoutique(b) {
  if (!b.distributeurs) return 'alerte';
  if (Number(b.references_suivies ?? 0) === 0) return 'dort';
  return 'ok';
}

function etatDistributeur(d) {
  if (Number(d.boutiques ?? 0) === 0) return 'alerte';
  if (Number(d.livreurs ?? 0) === 0) return 'alerte';
  if (Number(d.livreurs_en_ligne ?? 0) === 0) return 'dort';
  return 'ok';
}

function entreesRail() {
  const f = filtreRail.trim().toLowerCase();
  const garde = (texte) => !f || String(texte ?? '').toLowerCase().includes(f);

  if (railActif === 'boutiques') {
    const gardees = etat.boutiques.filter(
      (b) => garde(b.nom) || garde(b.commune) || garde(b.gerant_nom) || garde(b.distributeurs));
    const groupes = new Map();
    for (const b of gardees) {
      const cle = b.commune || '—';
      if (!groupes.has(cle)) groupes.set(cle, []);
      groupes.get(cle).push({
        id: b.point_de_vente_id,
        titre: b.nom,
        detail: b.distributeurs ? `Chez ${b.distributeurs}` : 'Personne ne la dessert',
        marge: `${nombre(b.references_suivies ?? 0)} réf.`,
        etat: etatBoutique(b),
      });
    }
    return [...groupes.entries()].sort((a, b) => a[0].localeCompare(b[0]));
  }

  if (railActif === 'distributeurs') {
    const gardees = etat.distributeurs.filter(
      (d) => garde(d.nom) || garde(d.fabricant_rattache) || garde(d.telephone));
    const groupes = new Map([['Affiliés', []], ['Indépendants', []]]);
    for (const d of gardees) {
      groupes.get(d.fabricant_rattache ? 'Affiliés' : 'Indépendants').push({
        id: d.distributeur_id,
        titre: d.nom,
        detail: `${nombre(d.boutiques ?? 0)} boutique(s) · ${nombre(d.livreurs ?? 0)} livreur(s)`,
        marge: Number(d.courses_en_attente ?? 0) > 0 ? `${d.courses_en_attente} ⏳` : '',
        etat: etatDistributeur(d),
      });
    }
    return [...groupes.entries()].filter(([, l]) => l.length);
  }

  const gardees = etat.marques.filter((m) => garde(m.fabricant_nom));
  return [['Marques du réseau', gardees.map((m) => {
    const boutiques = etat.boutiques.filter(
      (b) => String(b.marques ?? '').split(', ').includes(m.fabricant_nom)).length;
    return {
      id: m.fabricant_id,
      titre: m.fabricant_nom,
      detail: `${nombre(boutiques)} boutique(s) portent cette marque`,
      marge: '',
      etat: boutiques === 0 ? 'dort' : 'ok',
    };
  })]];
}

function tracerRail() {
  const boite = document.getElementById('railListe');
  const groupes = entreesRail();
  const total = groupes.reduce((s, [, l]) => s + l.length, 0);

  if (!total) {
    boite.innerHTML = `<div class="rail-vide">${
      filtreRail ? 'Rien ne correspond à cette recherche.'
        : 'Rien à afficher pour l’instant.'}</div>`;
    return;
  }

  boite.innerHTML = groupes.map(([nom, liste]) => `
    <div class="rail-groupe"><span>${echapper(nom)}</span><span>${liste.length}</span></div>
    ${liste.map((e) => `<button type="button" class="rail-entree${
      selection && selection.type === railActif && selection.id === e.id ? ' est-choisi' : ''
    }" data-id="${echapper(e.id)}">
      <i data-etat="${e.etat}"></i>
      <span><strong>${echapper(e.titre)}</strong><em>${echapper(e.detail)}</em></span>
      ${e.marge ? `<b>${echapper(e.marge)}</b>` : ''}
    </button>`).join('')}`).join('');

  for (const bouton of boite.querySelectorAll('.rail-entree')) {
    bouton.addEventListener('click', () => {
      selection = { type: railActif, id: bouton.dataset.id };
      tracerRail();
      tracerCarte();
      tracerTiroir();
    });
  }
}

for (const onglet of document.querySelectorAll('.rail-onglet')) {
  onglet.addEventListener('click', () => {
    railActif = onglet.dataset.rail;
    selection = null;
    for (const o of document.querySelectorAll('.rail-onglet')) {
      o.classList.toggle('est-actif', o === onglet);
    }
    tracerRail();
    tracerCarte();
    tracerTiroir();
  });
}

document.getElementById('rechercheRail').addEventListener('input', (e) => {
  filtreRail = e.target.value;
  tracerRail();
});

/* ══ La carte ═════════════════════════════════════════════

   PAS DE FOND DE CARTE, ET C'EST UN CHOIX. Charger des tuiles obligerait à
   ouvrir `img-src` vers un hébergeur extérieur dans la politique de sécurité
   du site, qui s'applique à toutes ses pages. Ce que l'administrateur doit
   lire ici, ce ne sont pas les rues : c'est où se trouvent ses boutiques les
   unes par rapport aux autres, lesquelles sont orphelines, et si une commune
   entière est vide. La position relative suffit à cela, et une échelle en
   kilomètres donne la mesure qui manquerait sinon.                          */

function projeter(boutiques) {
  const points = boutiques.filter(
    (b) => Number.isFinite(Number(b.latitude)) && Number.isFinite(Number(b.longitude)));
  if (!points.length) return null;

  const lats = points.map((b) => Number(b.latitude));
  const lons = points.map((b) => Number(b.longitude));

  let latMin = Math.min(...lats);
  let latMax = Math.max(...lats);
  let lonMin = Math.min(...lons);
  let lonMax = Math.max(...lons);

  // Une seule boutique, ou plusieurs collées : sans cette ouverture minimale
  // l'étendue serait nulle et la division qui suit rendrait NaN. Deux
  // centièmes de degré valent un peu plus de deux kilomètres, soit l'échelle
  // d'un quartier d'Abidjan.
  const ETENDUE_MIN = 0.02;
  if (latMax - latMin < ETENDUE_MIN) {
    const c = (latMax + latMin) / 2;
    latMin = c - ETENDUE_MIN / 2; latMax = c + ETENDUE_MIN / 2;
  }
  if (lonMax - lonMin < ETENDUE_MIN) {
    const c = (lonMax + lonMin) / 2;
    lonMin = c - ETENDUE_MIN / 2; lonMax = c + ETENDUE_MIN / 2;
  }

  const marge = 0.16;
  const dLat = (latMax - latMin) * (1 + marge * 2);
  const dLon = (lonMax - lonMin) * (1 + marge * 2);
  latMin -= (latMax - latMin) * marge;
  lonMin -= (lonMax - lonMin) * marge;

  const L = 900;
  const H = 470;

  return {
    L,
    H,
    points,
    latMin,
    lonMin,
    dLat,
    dLon,
    // La latitude monte vers le nord, l'axe Y d'un SVG descend : l'inversion
    // n'est pas un détail, sans elle la carte est à l'envers.
    x: (lon) => ((lon - lonMin) / dLon) * L,
    y: (lat) => H - ((lat - latMin) / dLat) * H,
  };
}

function tracerCarte() {
  const boite = document.getElementById('canevasCarte');
  const echelle = document.getElementById('canevasEchelle');
  const sous = document.getElementById('canevasSous');

  const actives = etat.boutiques.filter((b) => b.statut === 'actif');
  const p = projeter(actives);

  if (!p) {
    boite.innerHTML =
      '<div class="canevas-vide">Aucune boutique recensée avec sa position. '
      + 'Le recensement se fait sur le terrain, depuis l’application : l’agent '
      + 'relève le point sur le pas de la porte, à moins de vingt-cinq mètres.</div>';
    echelle.hidden = true;
    return;
  }

  const n = p.points.length;
  sous.textContent = `${n} boutique${n > 1 ? 's' : ''} située${n > 1 ? 's' : ''}. `
    + 'Position relevée par l’agent recenseur, sur le pas de la porte.';

  // Une trame de fond, pour que l'œil ait une référence de distance. Elle n'a
  // aucune signification géographique et reste très discrète, pour ne pas se
  // faire prendre pour un réseau de rues.
  const trame = Array.from({ length: 11 }, (_, i) => {
    const x = (i / 10) * p.L;
    const y = (i / 10) * p.H;
    return `<line x1="${x.toFixed(0)}" y1="0" x2="${x.toFixed(0)}" y2="${p.H}" stroke="rgba(255,255,255,.05)"/>`
      + `<line x1="0" y1="${y.toFixed(0)}" x2="${p.L}" y2="${y.toFixed(0)}" stroke="rgba(255,255,255,.05)"/>`;
  }).join('');

  const marqueurs = p.points.map((b) => {
    const x = p.x(Number(b.longitude));
    const y = p.y(Number(b.latitude));
    const choisi = selection && selection.type === 'boutiques'
      && selection.id === b.point_de_vente_id;
    return `<g class="pt${choisi ? ' est-choisi' : ''}" data-etat="${etatBoutique(b)}"
              data-id="${echapper(b.point_de_vente_id)}" role="button" tabindex="0">
      <title>${echapper(b.nom)} — ${echapper(b.commune ?? '')}</title>
      <circle class="halo" cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="15"/>
      <circle class="corps" cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="7"/>
      <text x="${(x + 13).toFixed(1)}" y="${(y + 4).toFixed(1)}">${echapper(b.nom)}</text>
    </g>`;
  }).join('');

  boite.innerHTML =
    `<svg viewBox="0 0 ${p.L} ${p.H}" preserveAspectRatio="xMidYMid meet" role="img"
          aria-label="Carte des boutiques du réseau">${trame}${marqueurs}</svg>`;

  for (const g of boite.querySelectorAll('.pt')) {
    const choisir = () => {
      railActif = 'boutiques';
      for (const o of document.querySelectorAll('.rail-onglet')) {
        o.classList.toggle('est-actif', o.dataset.rail === 'boutiques');
      }
      selection = { type: 'boutiques', id: g.dataset.id };
      tracerRail();
      tracerCarte();
      tracerTiroir();
    };
    g.addEventListener('click', choisir);
    g.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); choisir(); }
    });
  }

  // L'échelle : un degré de latitude vaut environ 111 km partout, et un degré
  // de longitude 111 km multipliés par le cosinus de la latitude. À Abidjan,
  // cinq degrés nord, la correction est négligeable mais elle est écrite
  // parce qu'elle cesserait de l'être ailleurs.
  const latMoyenne = p.latMin + p.dLat / 2;
  const kmParDegreLon = 111.32 * Math.cos((latMoyenne * Math.PI) / 180);
  const kmTotal = p.dLon * kmParDegreLon;
  const kmBarre = [0.2, 0.5, 1, 2, 5, 10, 20, 50].find((k) => k > kmTotal / 5) ?? 100;
  const partBarre = Math.min(0.4, kmBarre / kmTotal);

  echelle.hidden = false;
  echelle.innerHTML = `${kmBarre < 1 ? `${kmBarre * 1000} m` : `${kmBarre} km`}`
    + `<hr style="width:${Math.round(partBarre * 190)}px">`;
}

/* ══ Le tiroir ════════════════════════════════════════════ */

function tracerTiroir() {
  const boite = document.getElementById('tiroir');

  if (!selection) {
    boite.innerHTML = `<div class="vide" style="border:0;background:transparent;padding:22px 0">
      <b>Rien de sélectionné</b>
      Choisissez une entrée dans la liste de gauche, ou un point sur la carte.
    </div>`;
    return;
  }

  if (selection.type === 'boutiques') {
    const b = etat.boutiques.find((x) => x.point_de_vente_id === selection.id);
    if (!b) { selection = null; return tracerTiroir(); }

    const refs = Number(b.references_suivies ?? 0);
    boite.innerHTML = `
      <div class="tiroir-tete">
        <div>
          <h3>${echapper(b.nom)}</h3>
          <p>${echapper(b.commune ?? '')} · ${echapper(b.type_activite ?? '')}${
            b.gerant_nom ? ` · ${echapper(b.gerant_nom)}` : ''}${
            b.telephone ? ` · <a href="tel:+${echapper(b.telephone)}">${echapper(telephoneLisible(b.telephone))}</a>` : ''}</p>
        </div>
        <div class="tiroir-actions">
          <button type="button" class="bouton" id="actionAttribuerBoutique">Attribuer à un distributeur</button>
        </div>
      </div>
      <div class="tiroir-faits">
        <div><small>Desservie par</small><span>${b.distributeurs
          ? echapper(b.distributeurs)
          : '<span class="etat etat--alerte">Personne</span>'}</span></div>
        <div><small>Marques</small><span>${echapper(b.marques ?? '—')}</span></div>
        <div><small>Références suivies</small><strong${refs === 0 ? ' data-ton="alerte"' : ''}>${nombre(refs)}</strong></div>
        <div><small>Ruptures ouvertes</small><strong${
          Number(b.ruptures_ouvertes ?? 0) > 0 ? ' data-ton="alerte"' : ''
        }>${nombre(b.ruptures_ouvertes ?? 0)}</strong></div>
        <div><small>Recensée par</small><span>${echapper(b.agent_recenseur ?? '—')}</span></div>
      </div>
      ${refs === 0 ? `<p class="note" style="margin:0">
        Cette boutique ne suit aucun stock. <b>La caisse ne peut donc déclencher
        aucune rupture automatique</b> : c'est le stock qui alerte en tombant à
        zéro. Le boutiquier doit faire son inventaire de départ depuis
        l'application.</p>` : ''}`;

    document.getElementById('actionAttribuerBoutique')
      .addEventListener('click', () => ouvrirAttribution(b.point_de_vente_id, b.nom));
    return;
  }

  if (selection.type === 'distributeurs') {
    const d = etat.distributeurs.find((x) => x.distributeur_id === selection.id);
    if (!d) { selection = null; return tracerTiroir(); }

    const livreurs = Number(d.livreurs ?? 0);
    const boutiques = Number(d.boutiques ?? 0);
    boite.innerHTML = `
      <div class="tiroir-tete">
        <div>
          <h3>${echapper(d.nom)}</h3>
          <p>${d.fabricant_rattache
            ? `Affilié à ${echapper(d.fabricant_rattache)}`
            : 'Distributeur indépendant'}${
            d.gerant ? ` · ${echapper(d.gerant)}` : ''}${
            d.telephone ? ` · <a href="tel:+${echapper(d.telephone)}">${echapper(telephoneLisible(d.telephone))}</a>` : ''}</p>
        </div>
        <div class="tiroir-actions">
          <button type="button" class="bouton" id="actionAttribuerDist">Lui attribuer une boutique</button>
        </div>
      </div>
      <div class="tiroir-faits">
        <div><small>Boutiques</small><strong${boutiques === 0 ? ' data-ton="alerte"' : ''}>${nombre(boutiques)}</strong></div>
        <div><small>Livreurs actifs</small><strong${livreurs === 0 ? ' data-ton="alerte"' : ''}>${nombre(livreurs)}</strong></div>
        <div><small>En ligne</small><strong>${nombre(d.livreurs_en_ligne ?? 0)}</strong></div>
        <div><small>Courses en attente</small><strong${
          Number(d.courses_en_attente ?? 0) > 0 ? ' data-ton="alerte"' : ''
        }>${nombre(d.courses_en_attente ?? 0)}</strong></div>
        <div><small>Auto-distribution</small><span>${d.auto_distribution ? 'Oui' : 'Non'}</span></div>
      </div>
      ${boutiques === 0 ? `<p class="note" style="margin:0">
        Ce distributeur ne voit aucune boutique, et <b>il ne peut pas en ajouter
        lui-même</b> : sa politique ne lui montre que les communes où il opère
        déjà, et il n'en a aucune. Sa première boutique doit lui être attribuée
        ici, sans quoi il ne commencera jamais.</p>` : ''}
      ${boutiques > 0 && livreurs === 0 ? `<p class="note" style="margin:0">
        Il voit ses courses et <b>ne peut les affecter à personne</b>. C'est à
        lui d'enrôler un livreur depuis l'application, onglet Flotte : le compte
        se remet en main propre.</p>` : ''}`;

    document.getElementById('actionAttribuerDist')
      .addEventListener('click', () => ouvrirAttribution(null, null, d.distributeur_id, d.nom));
    return;
  }

  const m = etat.marques.find((x) => x.fabricant_id === selection.id);
  if (!m) { selection = null; return tracerTiroir(); }

  const portee = etat.boutiques.filter(
    (b) => String(b.marques ?? '').split(', ').includes(m.fabricant_nom));
  const distributeurs = etat.distributeurs.filter((d) => d.fabricant_rattache === m.fabricant_nom);

  boite.innerHTML = `
    <div class="tiroir-tete">
      <div>
        <h3>${echapper(m.fabricant_nom)}</h3>
        <p>Marque du réseau</p>
      </div>
    </div>
    <div class="tiroir-faits">
      <div><small>Boutiques la portant</small><strong${
        portee.length === 0 ? ' data-ton="alerte"' : ''}>${nombre(portee.length)}</strong></div>
      <div><small>Distributeurs affiliés</small><strong>${nombre(distributeurs.length)}</strong></div>
      <div><small>Ruptures ouvertes</small><strong>${
        nombre(portee.reduce((s, b) => s + Number(b.ruptures_ouvertes ?? 0), 0))}</strong></div>
    </div>
    <p class="note" style="margin:0">
      Le détail du catalogue et le taux de service de cette marque appartiennent
      à son tableau de bord fabricant. <b>Vous voyez son emprise sur le réseau,
      pas son commerce.</b>
    </p>`;
}

/* ══ Les demandes ═════════════════════════════════════════ */

const PROFILS = {
  fabricant: 'Fabricant',
  distributeur_affilie: 'Distributeur affilié',
  distributeur_independant: 'Distributeur indépendant',
};

function tracerDemandes() {
  const zone = document.getElementById('zoneDemandes');
  const attente = etat.demandes.filter((d) => d.statut === 'en_attente');

  if (!attente.length) {
    zone.innerHTML = `<div class="vide">
      <b>Aucune demande en attente</b>
      Les inscriptions déposées depuis le site apparaissent ici, et personne
      n'obtient de compte sans passer par cet écran.
    </div>`;
    return;
  }

  // Les plus anciennes en tête : une demande oubliée est un professionnel qui
  // attend un appel et finit par renoncer.
  const ordonnees = [...attente].sort(
    (a, b) => Number(b.anciennete_secondes ?? 0) - Number(a.anciennete_secondes ?? 0));

  zone.innerHTML = `<div class="demandes">${ordonnees.map((d) => {
    const details = [
      d.ville ? ['Ville', d.ville] : null,
      d.communes ? ['Communes', d.communes] : null,
      d.marques ? ['Marques', d.marques] : null,
      d.email ? ['E-mail', d.email] : null,
    ].filter(Boolean);

    return `<article class="demande">
      <div class="demande-tete">
        <div>
          <strong>${echapper(d.societe)}</strong>
          <em>${echapper(d.nom)} · <a href="tel:+${echapper(d.telephone)}">${
            echapper(telephoneLisible(d.telephone))}</a></em>
        </div>
        <span class="etat etat--ok">${echapper(PROFILS[d.profil] ?? d.profil)}</span>
      </div>
      ${details.length ? `<ul class="demande-details">${
        details.map(([k, v]) => `<li><b>${echapper(k)} :</b> ${echapper(v)}</li>`).join('')
      }</ul>` : ''}
      ${d.message ? `<p class="demande-mot">« ${echapper(d.message)} »</p>` : ''}
      <div class="demande-pied">
        <small>Déposée ${anciennete(d.anciennete_secondes)}</small>
        <div class="demande-actions">
          <button type="button" class="bouton bouton--danger"
                  data-refuser="${echapper(d.demande_id)}"
                  data-societe="${echapper(d.societe)}">Refuser</button>
          <button type="button" class="bouton"
                  data-valider="${echapper(d.demande_id)}">Valider</button>
        </div>
      </div>
    </article>`;
  }).join('')}</div>`;

  for (const bouton of zone.querySelectorAll('[data-valider]')) {
    bouton.addEventListener('click', () =>
      ouvrirValidation(ordonnees.find((d) => d.demande_id === bouton.dataset.valider)));
  }
  for (const bouton of zone.querySelectorAll('[data-refuser]')) {
    bouton.addEventListener('click', () => refuser(bouton.dataset));
  }
}

function ouvrirValidation(demande) {
  if (!demande) return;
  demandeEnCours = demande;

  document.getElementById('sousTitreValidation').textContent =
    `${demande.societe} · ${PROFILS[demande.profil] ?? demande.profil} · `
    + telephoneLisible(demande.telephone);

  // Un distributeur affilié porte la marque d'un fabricant, et ce rattachement
  // décide de ce qu'il verra. Un indépendant n'en a pas, un fabricant encore
  // moins : le champ ne s'affiche que là où il a un sens.
  const affilie = demande.profil === 'distributeur_affilie';
  document.getElementById('champMarque').hidden = !affilie;

  if (affilie) {
    const select = document.getElementById('marqueRattachee');
    select.innerHTML = etat.marques.length
      ? etat.marques.map((f) =>
        `<option value="${echapper(f.fabricant_id)}">${echapper(f.fabricant_nom)}</option>`).join('')
      : '<option value="">Aucune marque enregistrée</option>';

    // La demande dit quelles marques le distributeur déclare porter. Si l'une
    // existe déjà, on la présélectionne : c'est presque toujours la bonne, et
    // cela évite une erreur de rattachement au clic.
    const declarees = String(demande.marques ?? '').toLowerCase();
    const trouvee = etat.marques.find((f) =>
      declarees.includes(String(f.fabricant_nom ?? '').toLowerCase()));
    if (trouvee) select.value = trouvee.fabricant_id;
  }

  document.getElementById('motDePasseGenere').value = motDePasseLisible();
  document.getElementById('messageValidation').hidden = true;
  fValidation.showModal();
}

document.getElementById('regenererMdp').addEventListener('click', () => {
  document.getElementById('motDePasseGenere').value = motDePasseLisible();
});

document.getElementById('annulerValidation').addEventListener('click', () => fValidation.close());

document.getElementById('confirmerValidation').addEventListener('click', async () => {
  if (!demandeEnCours) return;

  const bouton = document.getElementById('confirmerValidation');
  const retour = document.getElementById('messageValidation');
  const motDePasse = document.getElementById('motDePasseGenere').value;
  const demande = demandeEnCours;

  const fabricant = demande.profil === 'fabricant';
  const affilie = demande.profil === 'distributeur_affilie';
  const marque = document.getElementById('marqueRattachee').value;

  if (affilie && !marque) {
    retour.textContent = 'Aucune marque à rattacher. Créez d’abord le fabricant, '
      + 'ou validez ce distributeur comme indépendant.';
    retour.dataset.ton = 'erreur';
    retour.hidden = false;
    return;
  }

  bouton.disabled = true;
  bouton.textContent = 'Création…';

  try {
    // La création passe par la fonction Edge, pas par la base : elle seule
    // détient la clé de service, qui ne peut pas entrer dans une page web.
    // C'est elle aussi qui marque la demande validée, dans le même geste.
    const reponse = await fetch(`${URL_BASE}/functions/v1/creer-compte`, {
      method: 'POST',
      headers: {
        apikey: CLE,
        Authorization: `Bearer ${jeton}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        nom: demande.nom,
        telephone: demande.telephone,
        role: fabricant ? 'fabricant' : 'distributeur',
        mot_de_passe: motDePasse,
        demande_id: demande.demande_id,
        details: {
          nom_societe: demande.societe,
          ...(affilie ? { fabricant_id: marque } : {}),
        },
      }),
    });

    const corps = await reponse.json().catch(() => ({}));
    if (!reponse.ok) throw new Error(corps.erreur || `HTTP ${reponse.status}`);

    fValidation.close();

    // Le mot de passe n'existe qu'ici, et cette fenêtre est la seule occasion
    // de le lire. Il n'est écrit nulle part ailleurs, volontairement.
    document.getElementById('identifiantCree').textContent =
      telephoneLisible(corps.identifiant ?? demande.telephone);
    document.getElementById('motDePasseCree').textContent = motDePasse;
    fIdentifiants.showModal();

    // Le compte existe, la demande n'a pas pu être marquée : l'incident est
    // rattrapable et il faut le dire, sinon l'administrateur revalidera et se
    // heurtera à « ce numéro est déjà rattaché à un compte ».
    if (corps.demande_traitee === false) {
      informer('Le compte est créé, mais la demande est restée en attente à '
        + 'l’écran. Ne la validez pas une seconde fois : le compte existe déjà.', 'erreur');
    }

    await rafraichir();
  } catch (erreur) {
    retour.textContent = erreur.message;
    retour.dataset.ton = 'erreur';
    retour.hidden = false;
  } finally {
    bouton.disabled = false;
    bouton.textContent = 'Créer le compte';
  }
});

async function refuser({ refuser: id, societe }) {
  const motif = prompt(
    `Refuser la demande de ${societe} ?\n\n`
    + 'Motif, pour la retrouver plus tard. Il n’est pas envoyé au demandeur.');
  // `prompt` rend null quand on annule, et la chaîne vide quand on valide sans
  // rien écrire. Seul le premier cas veut dire « je renonce ».
  if (motif === null) return;

  try {
    await interroger('rpc/refuser_demande_acces', {
      method: 'POST',
      body: JSON.stringify({ p_demande_id: id, p_motif: motif || null }),
    });
    await rafraichir();
  } catch (erreur) {
    if (erreur.message === 'session') return;
    informer(erreur.message, 'erreur');
  }
}

/* ══ Les anomalies ════════════════════════════════════════ */

const ANOMALIES = {
  boutique_sans_distributeur: 'Boutique sans distributeur',
  distributeur_sans_livreur: 'Distributeur sans livreur',
  boutique_sans_stock: 'Boutique sans stock suivi',
  rupture_sans_destinataire: 'Rupture sans destinataire',
};

function tracerAnomalies() {
  const zone = document.getElementById('zoneAnomalies');

  if (!etat.anomalies.length) {
    zone.innerHTML = `<div class="vide">
      <b>Rien à signaler</b>
      Chaque boutique active a son distributeur et son stock suivi, chaque
      distributeur a son livreur, et chaque rupture a un destinataire.
    </div>`;
    return;
  }

  const familles = new Map();
  for (const a of etat.anomalies) {
    if (!familles.has(a.type_anomalie)) familles.set(a.type_anomalie, []);
    familles.get(a.type_anomalie).push(a);
  }

  zone.innerHTML = [...familles.entries()].map(([type, liste]) => {
    const attribuable = type === 'boutique_sans_distributeur';
    return `<section class="famille">
      <div class="famille-tete">
        <h3>${echapper(ANOMALIES[type] ?? type)}</h3>
        <b>${liste.length}</b>
        <p>${echapper(liste[0].consequence ?? '')}</p>
      </div>
      <div class="table-boite"><table class="table">
        <thead><tr><th>Objet</th><th>Où</th><th></th></tr></thead>
        <tbody>${liste.map((a) => `<tr>
          <td>${echapper(a.objet_nom)}</td>
          <td>${echapper(a.detail ?? '')}</td>
          <td style="text-align:end">${attribuable
            ? `<button type="button" class="bouton bouton--creux"
                 data-attribuer="${echapper(a.objet_id)}"
                 data-nom="${echapper(a.objet_nom)}">Attribuer</button>`
            : '<span style="opacity:.4">—</span>'}</td>
        </tr>`).join('')}</tbody>
      </table></div>
    </section>`;
  }).join('');

  for (const bouton of zone.querySelectorAll('[data-attribuer]')) {
    bouton.addEventListener('click', () =>
      ouvrirAttribution(bouton.dataset.attribuer, bouton.dataset.nom));
  }
}

/* ══ Attribuer ════════════════════════════════════════════ */

/* La même fenêtre s'ouvre depuis deux endroits : depuis une boutique, où le
   distributeur reste à choisir, et depuis un distributeur, où c'est la
   boutique. On verrouille ce qui est déjà connu plutôt que de le redemander. */
function ouvrirAttribution(boutiqueId, boutiqueNom, distributeurId, distributeurNom) {
  distributeurEnCours = distributeurId ?? null;

  const selBoutique = document.getElementById('boutiqueChoisie');
  const selMarque = document.getElementById('marqueChoisie');

  selMarque.innerHTML = etat.marques.length
    ? etat.marques.map((f) =>
      `<option value="${echapper(f.fabricant_id)}">${echapper(f.fabricant_nom)}</option>`).join('')
    : '<option value="">Aucune marque enregistrée</option>';

  if (distributeurId) {
    document.getElementById('sousTitreAttribution').textContent =
      `Vers ${distributeurNom}. Choisissez la boutique à lui confier.`;
    selBoutique.disabled = false;
    selBoutique.innerHTML = etat.boutiques.map((b) =>
      `<option value="${echapper(b.point_de_vente_id)}">${echapper(b.nom)} · ${
        echapper(b.commune ?? '')}${b.distributeurs
        ? ` (chez ${echapper(b.distributeurs)})` : ' (libre)'}</option>`).join('');
  } else {
    document.getElementById('sousTitreAttribution').textContent =
      `${boutiqueNom}. Choisissez le distributeur qui la desservira.`;
    selBoutique.disabled = true;
    selBoutique.innerHTML =
      `<option value="${echapper(boutiqueId)}">${echapper(boutiqueNom)}</option>`;
  }

  document.getElementById('champDistributeur').hidden = Boolean(distributeurId);
  if (!distributeurId) {
    document.getElementById('distributeurChoisi').innerHTML = etat.distributeurs.length
      ? etat.distributeurs.map((d) =>
        `<option value="${echapper(d.distributeur_id)}">${echapper(d.nom)}${
          d.fabricant_rattache ? ` · ${echapper(d.fabricant_rattache)}` : ''}</option>`).join('')
      : '<option value="">Aucun distributeur enregistré</option>';
  }

  document.getElementById('messageAttribution').hidden = true;
  fAttribution.showModal();
}

document.getElementById('annulerAttribution').addEventListener('click', () => fAttribution.close());

document.getElementById('confirmerAttribution').addEventListener('click', async () => {
  const bouton = document.getElementById('confirmerAttribution');
  const retour = document.getElementById('messageAttribution');

  const boutique = document.getElementById('boutiqueChoisie').value;
  const marque = document.getElementById('marqueChoisie').value;
  const distributeur = distributeurEnCours
    ?? document.getElementById('distributeurChoisi').value;

  if (!boutique || !marque || !distributeur) {
    retour.textContent = 'Il manque la boutique, la marque ou le distributeur.';
    retour.dataset.ton = 'erreur';
    retour.hidden = false;
    return;
  }

  bouton.disabled = true;
  bouton.textContent = 'Attribution…';

  try {
    const resultat = await interroger('rpc/attribuer_boutique_admin', {
      method: 'POST',
      body: JSON.stringify({
        p_point_de_vente_id: boutique,
        p_fabricant_id: marque,
        p_distributeur_id: distributeur,
      }),
    });

    fAttribution.close();

    // Reprendre une boutique à un confrère est une décision commerciale, pas un
    // détail technique. La base rend le nom du distributeur dépossédé pour que
    // l'écran puisse le dire, plutôt que d'annoncer un succès muet.
    informer(
      resultat.repris_a
        ? `${resultat.boutique} passe de ${resultat.repris_a} à ${resultat.distributeur} `
          + `pour ${resultat.marque}.`
        : `${resultat.boutique} est confiée à ${resultat.distributeur} pour ${resultat.marque}.`,
      'succes');
    await rafraichir();
  } catch (erreur) {
    if (erreur.message === 'session') return;
    retour.textContent = erreur.message;
    retour.dataset.ton = 'erreur';
    retour.hidden = false;
  } finally {
    bouton.disabled = false;
    bouton.textContent = 'Attribuer';
  }
});

/* ══ Chargement ═══════════════════════════════════════════ */

function tracerBadges() {
  const demandes = etat.demandes.filter((d) => d.statut === 'en_attente').length;
  const anomalies = etat.anomalies.length;

  const bDemandes = document.getElementById('compteurDemandes');
  bDemandes.textContent = demandes;
  bDemandes.hidden = demandes === 0;
  bDemandes.dataset.urgent = demandes > 0 ? 'oui' : 'non';

  const bAnomalies = document.getElementById('compteurAnomalies');
  bAnomalies.textContent = anomalies;
  bAnomalies.hidden = anomalies === 0;
  bAnomalies.dataset.urgent = anomalies > 0 ? 'oui' : 'non';
}

async function rafraichir() {
  try {
    const [reseau, demandes, anomalies, distributeurs, boutiques, marques, activite] =
      await Promise.all([
        interroger('v_supervision_reseau?select=*'),
        interroger('v_demandes_acces?select=*&order=created_at.desc'),
        interroger('v_anomalies_reseau?select=*&order=type_anomalie,depuis'),
        interroger('v_supervision_distributeurs?select=*&order=nom'),
        interroger('v_supervision_boutiques?select=*&order=commune,nom'),
        // La table plutôt que la vue de tableau de bord du fabricant : on n'a
        // besoin que des noms pour remplir des sélecteurs, et cette vue-là est
        // désormais filtrée sur la ligne de l'appelant.
        interroger('fabricants?select=fabricant_id:id,fabricant_nom:nom&statut=eq.actif&order=nom'),
        interroger('v_supervision_activite?select=*&order=jour'),
      ]);

    etat = {
      reseau: reseau[0] ?? {},
      demandes,
      anomalies,
      distributeurs,
      boutiques,
      marques,
      activite,
    };

    tracerBadges();
    tracerJauge(etat.reseau.taux_de_service_pct);
    tracerAnneau();
    tracerCouverture();
    tracerActivite();
    tracerChiffres();
    tracerCommunes();
    tracerCharge();
    tracerRail();
    tracerCarte();
    tracerTiroir();
    tracerDemandes();
    tracerAnomalies();

    const heure = new Date().toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
    pouls.textContent = `lu à ${heure}`;
    pouls.dataset.etat = 'ok';
  } catch (erreur) {
    if (erreur.message === 'session') return;
    pouls.dataset.etat = 'perdu';
    informer('Les données n’ont pas pu être rafraîchies. Sur ce réseau, un appel '
      + 'sur dix se coupe : la prochaine tentative part dans trente secondes.', 'erreur');
  }
}

if (jeton) {
  document.getElementById('nomAdmin').textContent = nomAdmin;
  document.getElementById('initiales').textContent = nomAdmin
    .split(/\s+/).filter(Boolean).slice(0, 2).map((m) => m[0].toUpperCase()).join('') || 'A';

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
