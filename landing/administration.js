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
const VERT = '#146B3A';
const VERT_VIF = '#74D18C';
const VERT_SOMBRE = '#102A23';
const JAUNE = '#FFE500';
const ALERTE = '#D65C52';

const message = document.getElementById('message');
const pouls = document.getElementById('pouls');
const pouls2 = document.getElementById('pouls2');

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
  acteurs: {},
  livreurs: [],
  communes: [],
  rupturesRecentes: [],
  attribution: [],
  semaines: [],
  parFabricant: [],
  produitsTendus: [],
  diffusions: [],
  soumissions: [],
};

let railActif = 'boutiques';
let filtreRail = '';
let filtreCommune = '';
let filtreCommuneTableau = '';
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

/* Le franc CFA n'a pas de décimale, et les montants du réseau se comptent en
   centaines de milliers. « 1,4 M » se lit d'un coup d'œil, « 1 412 500 » se
   déchiffre. Le montant exact reste disponible au survol. */
function montant(valeur) {
  const v = Number(valeur ?? 0);
  if (!Number.isFinite(v)) return '—';
  if (v >= 1000000) return `${(v / 1000000).toFixed(1).replace('.', ',')} M`;
  if (v >= 10000) return `${Math.round(v / 1000)} k`;
  return nombre(Math.round(v));
}

function montantExact(valeur) {
  return `${nombre(Math.round(Number(valeur ?? 0)))} F CFA`;
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

/* Mot de passe dicté de vive voix, jamais lu sur un écran par celui qui le tape.

   TOUT EN MAJUSCULES, et c'est le point essentiel. Une majuscule et une
   minuscule de la même lettre se prononcent exactement pareil : dicter « d »
   sans préciser la casse fait taper l'une pour l'autre une fois sur deux, et la
   connexion est refusée sans que personne ne comprenne pourquoi. C'est arrivé
   sur le compte de l'agent recenseur, le jour du premier test de terrain.

   Ni I ni O ni 0 ni 1 non plus, qui se confondent à la lecture. Huit
   caractères, le même alphabet que les scripts et que l'application. */
function motDePasseLisible() {
  const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
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
  acteurs: 'voletActeurs',
  diffusion: 'voletDiffusion',
  statistiques: 'voletStatistiques',
  anomalies: 'voletAnomalies',
};

function ouvrirVolet(nom) {
  for (const [cle, id] of Object.entries(VOLETS)) {
    document.getElementById(id).hidden = cle !== nom;
  }
  for (const onglet of document.querySelectorAll('.console-onglet')) {
    onglet.classList.toggle('est-actif', onglet.dataset.volet === nom);
  }
  // La barre latérale regroupe plusieurs volets réels sous une même entrée
  // (« Acteurs du réseau » couvre à la fois Acteurs et Diffusion) : ce bouton
  // doit rester allumé tant qu'on est sur l'un des deux.
  for (const bouton of document.querySelectorAll('.console-nav > [data-groupe]')) {
    const membres = bouton.dataset.groupe.split(',');
    bouton.classList.toggle('est-actif', membres.includes(nom));
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
  // La maquette n'affiche le taux de service que comme chiffre de KPI,
  // sans grande jauge dédiée : la carte ronde a été retirée du bas de page,
  // mais le calcul (et son texte d'accompagnement court) reste utile au pied
  // de la carte KPI « Taux de service ».
  const kpi = document.getElementById('chiffreService');
  const detailKpi = document.getElementById('detailService');
  const closes = Number(etat.reseau.ruptures_closes ?? 0);

  if (valeur === null || valeur === undefined) {
    if (kpi) kpi.textContent = '—';
    if (detailKpi) detailKpi.textContent = 'Aucune demande clôturée';
    return;
  }

  const v = Math.max(0, Math.min(100, Number(valeur)));
  if (kpi) kpi.textContent = `${v} %`;
  if (detailKpi) detailKpi.textContent = `Sur ${nombre(closes)} demande(s) clôturée(s)`;
}

/* ── L'anneau des ruptures ────────────────────────────────
   Trois états, et ils ne se corrigent pas au même endroit : à confirmer, c'est
   le boutiquier qui doit répondre ; ouverte, c'est le distributeur qui doit
   prendre ; prise en charge, c'est le livreur qui roule. */
function tracerAnneau() {
  const boite = document.getElementById('demandesEnCoursListe');
  const pied = document.getElementById('piedRuptures');

  const enCours = etat.rupturesRecentes.filter((r) => r.statut !== 'prise_en_charge');
  const total = enCours.length;

  if (!total) {
    boite.innerHTML = '<div class="vide" style="border:0;padding:12px 0">'
      + 'Aucune demande en cours. Tous les revendeurs du réseau sont servis.</div>';
  } else {
    const ordonnees = [...enCours]
      .sort((a, b) => Number(b.attente_secondes ?? 0) - Number(a.attente_secondes ?? 0))
      .slice(0, 6);

    boite.innerHTML = ordonnees.map((r) => {
      const attente = Number(r.attente_secondes ?? 0);
      // Deux heures : c'est le seuil d'escalade utilisé partout ailleurs
      // dans le produit. Au-delà, la barre de progression est pleine.
      const progression = Math.min(100, Math.round((attente / 7200) * 100));
      return `<div class="signal-item">
        <div class="signal-heading">
          <strong>${echapper(r.produit)} · ${echapper(r.point_de_vente)}</strong>
          <span class="status${r.confirmee_le ? '' : ''}">${r.confirmee_le ? 'En attente' : 'À confirmer'}</span>
        </div>
        <div class="signal-meta"><span>${echapper(r.commune ?? '')}${
          r.distributeur ? ` · ${echapper(r.distributeur)}` : ' · Sans distributeur'}</span><span>${duree(attente)}</span></div>
        <div class="signal-meter"><i style="width:${progression}%"></i></div>
      </div>`;
    }).join('');
  }

  const sansPreneur = enCours.filter((r) => r.statut === 'signalee' && !r.distributeur).length;
  pied.textContent = total === 0
    ? 'Aucune demande en cours. Tous les revendeurs du réseau sont servis.'
    : sansPreneur > 0
      ? `${sansPreneur} attend${sansPreneur > 1 ? 'ent' : ''} la confirmation du revendeur : `
        + 'elles ne seront visibles des distributeurs qu’après sa confirmation.'
      : 'Toutes les demandes en cours sont confirmées et visibles des distributeurs.';
}

/* ── La couverture du réseau ──────────────────────────────
   Le seuil à 100 % n'est pas décoratif : une boutique sans distributeur
   produit des ruptures sans destinataire, qui n'existent qu'après deux heures
   d'escalade. C'est la seule barre de cet écran dont l'objectif est absolu. */
function tracerCouverture() {
  const anneau = document.getElementById('anneauCouverture');
  const valeur = document.getElementById('valeurCouverture');
  const copie = document.getElementById('texteCouverture');
  const barres = document.getElementById('communesCouverture');
  const pied = document.getElementById('piedCouverture');

  const actives = etat.boutiques.filter((b) => b.statut === 'actif');
  const desservies = actives.filter((b) => b.distributeurs);
  const total = actives.length;
  const part = total === 0 ? 0 : Math.round((desservies.length / total) * 100);

  anneau.style.background = `conic-gradient(${VERT} 0 ${part}%, #e6ebe5 ${part}% 100%)`;
  valeur.textContent = `${part} %`;
  copie.innerHTML = `<strong>${nombre(desservies.length)} revendeur(s) desservi(s)</strong>`
    + `<p>Sur ${nombre(total)} revendeur(s) actif(s) au total.</p>`;

  const filtres = actives.filter((b) => !filtreCommuneTableau || b.commune === filtreCommuneTableau);
  const parCommune = new Map();
  for (const b of filtres) {
    const cle = b.commune || '—';
    if (!parCommune.has(cle)) parCommune.set(cle, { desservies: 0, total: 0 });
    const ligne = parCommune.get(cle);
    ligne.total += 1;
    if (b.distributeurs) ligne.desservies += 1;
  }

  const rangs = [...parCommune.entries()]
    .map(([commune, v]) => ({ commune, ...v, taux: v.total === 0 ? 0 : Math.round((v.desservies / v.total) * 100) }))
    .sort((a, b) => b.total - a.total)
    .slice(0, 6);

  barres.innerHTML = !rangs.length
    ? '<div class="vide" style="border:0;padding:8px 0">Aucun revendeur actif.</div>'
    : rangs.map((r) => `<div class="commune-row">
        <span>${echapper(r.commune)}</span>
        <div class="track"><i style="width:${r.taux}%"></i></div>
        <b>${r.taux} %</b>
      </div>`).join('');

  const orphelines = total - desservies.length;
  pied.textContent = total === 0
    ? 'Aucun revendeur actif. Le recensement se fait sur le terrain, depuis l’application.'
    : orphelines === 0
      ? 'Chaque revendeur actif a son distributeur. C’est l’état normal du réseau.'
      : `${orphelines} revendeur(s) que personne ne dessert : leurs demandes `
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
         aria-label="Demandes reçues et livraisons confirmées sur quatorze jours">
      ${grilles}${barres}${ligne}${dates}
    </svg>
    <div class="legende" style="flex-direction:row;gap:18px;margin-top:10px">
      <div style="flex:0"><i style="background:${ALERTE}"></i>Demandes</div>
      <div style="flex:0"><i style="background:${VERT}"></i>Livraisons</div>
    </div>`;

  const signalees = jours.reduce((s, j) => s + Number(j.signalees), 0);
  const resolues = jours.reduce((s, j) => s + Number(j.resolues), 0);
  pied.textContent = signalees === 0 && resolues === 0
    ? 'Rien n’a bougé sur ces quatorze jours. Le pilote n’a pas encore généré de demande.'
    : `${nombre(signalees)} demande(s) reçue(s) et ${nombre(resolues)} livraison(s) confirmée(s) sur la période. `
      + (resolues >= signalees
        ? 'Le réseau absorbe ce qu’il reçoit.'
        : 'Le réseau reçoit plus de demandes qu’il ne livre : l’écart se creuse.');
}

/* ── Le réseau en chiffres ────────────────────────────────
   Une table plutôt que six cartes à gros chiffre : ce sont des grandeurs de
   nature différente, qu'on lit par comparaison et pas par saisissement. */
function tracerChiffres() {
  const r = etat.reseau;
  const lignes = [
    ['Revendeurs actifs', r.boutiques_actives, r.boutiques_total !== r.boutiques_actives
      ? `${nombre(r.boutiques_total)} revendeur(s) recensé(s)` : ''],
    ['Distributeurs', r.distributeurs, ''],
    ['Livreurs en ligne', r.livreurs_en_ligne, `${nombre(r.livreurs_actifs)} actif(s) dans les flottes`],
    ['Marques', r.fabricants, `${nombre(r.produits)} référence(s) au catalogue`],
    ['Demandes en attente', r.demandes_en_attente, ''],
  ];

  document.getElementById('tableChiffres').innerHTML = lignes.map(([nom, valeur, detail]) => `
    <div class="network-stat">
      <strong>${nombre(valeur)}</strong>
      <span>${echapper(nom)}${detail ? ` · ${echapper(detail)}` : ''}</span>
    </div>`).join('');
}

/* ── La charge des distributeurs ──────────────────────────
   Pas de coût ni de remise : on affiche la seule donnée réelle, le nombre de
   demandes à livrer, classée du plus chargé au moins chargé. */
function tracerCharge() {
  const boite = document.getElementById('chargesApercuListe');
  const liste = [...etat.distributeurs]
    .sort((a, b) => Number(b.courses_en_attente ?? 0) - Number(a.courses_en_attente ?? 0));

  if (!liste.length) {
    boite.innerHTML = '<div class="vide" style="border:0;padding:12px 0">Aucun distributeur enregistré.</div>';
    return;
  }

  const maxi = Math.max(1, ...liste.map((d) => Number(d.courses_en_attente ?? 0)));

  boite.innerHTML = liste.slice(0, 6).map((d) => {
    const attente = Number(d.courses_en_attente ?? 0);
    const livreurs = Number(d.livreurs ?? 0);
    const largeur = Math.round((attente / maxi) * 100);
    return `<div class="rank-item">
      <div class="rank-heading"><strong>${echapper(d.nom)}</strong><span>${nombre(attente)}</span></div>
      <div class="rank-meter"><i style="width:${largeur}%"></i></div>
      <div class="rank-sub">${nombre(d.boutiques ?? 0)} revendeur(s) · ${nombre(livreurs)} livreur(s)${
        livreurs === 0 ? ' · aucun livreur actif' : ''}</div>
    </div>`;
  }).join('');
}

/* ── Les nouveaux revendeurs, calculés sur le recensement réel ────────── */
function tracerMetriques() {
  const cible = document.getElementById('metricNouveaux');
  if (!cible) return;
  const seuil = Date.now() - 30 * 24 * 3600 * 1000;
  const recents = etat.boutiques.filter((b) => b.created_at && new Date(b.created_at).getTime() >= seuil);
  cible.textContent = nombre(recents.length);
}

/* ── Prévision et valeur des livraisons ────────────────────
   Seule la valeur des livraisons confirmées existe réellement (le bandeau de
   confidentialité l'explique) : le reste est annoncé « non calculable »
   plutôt qu'inventé, comme le fait déjà le prototype. */
function tracerPrevision() {
  const boite = document.getElementById('previsionListe');
  if (!boite) return;
  const jours = etat.activite;
  const aujourdhui = jours.length ? jours[jours.length - 1] : null;
  const duJour = Number(aujourdhui?.montant ?? 0);
  const livraisons = Number(aujourdhui?.livraisons ?? 0);
  const panier = livraisons > 0 ? duJour / livraisons : null;
  const maxi = Math.max(duJour, 1);

  boite.innerHTML = `
    <div class="finance-item">
      <div class="finance-label"><span>CA livré confirmé (estimation logistique)</span><strong>${montant(duJour)}</strong></div>
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

/* ── Les livreurs les plus actifs, sur l'historique disponible ────────── */
function tracerLivreursEfficaces() {
  const boite = document.getElementById('livreursEfficacesListe');
  if (!boite) return;
  const classes = [...etat.livreurs]
    .map((l) => ({ ...l, termine: Number(l.livraisons_terminees ?? 0) }))
    .filter((l) => l.termine > 0)
    .sort((a, b) => b.termine - a.termine)
    .slice(0, 6);

  if (!classes.length) {
    boite.innerHTML = '<div class="vide" style="border:0;padding:12px 0;color:#a9b9ae">'
      + 'Non suivi : aucune livraison terminée n’est encore enregistrée.</div>';
    return;
  }

  const maxi = Math.max(1, ...classes.map((l) => l.termine));
  boite.innerHTML = classes.map((l) => `<div class="rank-item">
    <div class="rank-heading"><strong>${echapper(l.nom ?? l.telephone ?? 'Livreur')}</strong><span>${nombre(l.termine)}</span></div>
    <div class="rank-meter"><i style="width:${Math.round((l.termine / maxi) * 100)}%"></i></div>
    <div class="rank-sub">Livraisons terminées, historique complet (pas de date ni de distance suivies)</div>
  </div>`).join('');
}

/* ── Les produits les plus demandés, aperçu de la liste complète ─────── */
function tracerProduitsApercu() {
  const boite = document.getElementById('produitsApercuListe');
  if (!boite) return;

  if (!etat.produitsTendus.length) {
    boite.innerHTML = '<div class="vide" style="border:0;padding:12px 0;color:#a9b9ae">'
      + 'Aucune demande enregistrée à ce jour.</div>';
    return;
  }

  const ordonnes = [...etat.produitsTendus]
    .sort((a, b) => Number(b.signalements) - Number(a.signalements))
    .slice(0, 6);
  const maxi = Math.max(1, ...ordonnes.map((p) => Number(p.signalements)));

  boite.innerHTML = ordonnes.map((p, i) => {
    const n = Number(p.signalements);
    return `<div class="product-row">
      <span class="product-rank">${i + 1}</span>
      <span class="product-name">${echapper(p.produit)}<br><small style="opacity:.75">${echapper(p.marque)}</small></span>
      <div class="product-bar"><i style="width:${Math.round((n / maxi) * 100)}%"></i></div>
      <span class="product-count">${nombre(n)} demande(s)</span>
    </div>`;
  }).join('');
}

/* ══ Le rail ══════════════════════════════════════════════ */

/* Le risque boutique qui compte pour le réseau : l'absence de distributeur. */
function etatBoutique(b) {
  if (!b.distributeurs) return 'alerte';
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
        marge: Number(b.ruptures_ouvertes ?? 0) > 0 ? `${nombre(b.ruptures_ouvertes)} demande(s)` : '',
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
        detail: `${nombre(d.boutiques ?? 0)} revendeur(s) · ${nombre(d.livreurs ?? 0)} livreur(s)`,
        marge: Number(d.courses_en_attente ?? 0) > 0 ? `${d.courses_en_attente} ⏳` : '',
        etat: etatDistributeur(d),
      });
    }
    return [...groupes.entries()].filter(([, l]) => l.length);
  }

  if (railActif === 'livreurs') {
    const gardees = etat.livreurs.filter(
      (l) => garde(l.nom) || garde(l.distributeur) || garde(l.commune_approchee));
    const groupes = new Map();
    for (const l of gardees) {
      const cle = l.distributeur || 'Sans flotte';
      if (!groupes.has(cle)) groupes.set(cle, []);
      const e = etatLivreur(l);
      groupes.get(cle).push({
        id: l.livreur_id,
        titre: l.nom,
        detail: `${e.texte}${l.commune_approchee ? ` · ${l.commune_approchee}` : ''}`,
        marge: Number(l.courses_en_cours ?? 0) > 0 ? `${l.courses_en_cours} ⏳` : '',
        etat: e.cle === 'course' ? 'ok' : e.cle,
      });
    }
    return [...groupes.entries()].sort((a, b) => a[0].localeCompare(b[0]));
  }

  const gardees = etat.marques.filter((m) => garde(m.fabricant_nom));
  return [['Marques du réseau', gardees.map((m) => {
    const boutiques = etat.boutiques.filter(
      (b) => String(b.marques ?? '').split(', ').includes(m.fabricant_nom)).length;
    return {
      id: m.fabricant_id,
      titre: m.fabricant_nom,
      detail: `${nombre(boutiques)} revendeur(s) portent cette marque`,
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

  const actives = etat.boutiques.filter(
    (b) => b.statut === 'actif' && (!filtreCommune || b.commune === filtreCommune));

  // Les livreurs entrent dans le cadrage avec les boutiques : une carte dont
  // le cadre ignore un livreur le pousse hors de l'image sans rien dire.
  const livreursSitues = etat.livreurs.filter((l) =>
    l.actif === true
    && Number.isFinite(Number(l.latitude)) && Number.isFinite(Number(l.longitude))
    && (!filtreCommune || l.commune_approchee === filtreCommune));

  const p = projeter([...actives, ...livreursSitues]);

  if (!p) {
    boite.innerHTML = `<div class="canevas-vide">${filtreCommune
      ? `Aucun revendeur situé à ${echapper(filtreCommune)}.`
      : 'Aucun revendeur recensé avec sa position. Le recensement se fait sur '
        + 'le terrain, depuis l’application : l’agent relève le point sur le pas '
        + 'de la porte, à moins de vingt-cinq mètres.'}</div>`;
    echelle.hidden = true;
    return;
  }

  const n = actives.filter((b) =>
    Number.isFinite(Number(b.latitude)) && Number.isFinite(Number(b.longitude))).length;
  sous.textContent = `${n} revendeur${n > 1 ? 's' : ''} situé${n > 1 ? 's' : ''}`
    + (livreursSitues.length ? `, ${livreursSitues.length} livreur(s) localisé(s)` : '')
    + (filtreCommune ? ` à ${filtreCommune}` : '') + '. '
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

  const marqueurs = actives.filter((b) =>
    Number.isFinite(Number(b.latitude)) && Number.isFinite(Number(b.longitude))).map((b) => {
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

  // Les livreurs se dessinent APRÈS les boutiques, donc au-dessus : ce sont
  // eux qui bougent, et c'est eux qu'on cherche du regard.
  const mobiles = livreursSitues.map((l) => {
    const x = p.x(Number(l.longitude));
    const y = p.y(Number(l.latitude));
    const e = etatLivreur(l);
    const choisi = selection && selection.type === 'livreurs' && selection.id === l.livreur_id;
    const c = 7;
    return `<g class="lv${choisi ? ' est-choisi' : ''}" data-etat="${e.cle}"
              data-id="${echapper(l.livreur_id)}" role="button" tabindex="0">
      <title>${echapper(l.nom)} — ${echapper(e.texte)}</title>
      <circle class="halo" cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="14"/>
      <path class="corps" d="M ${x.toFixed(1)} ${(y - c).toFixed(1)}
        L ${(x + c).toFixed(1)} ${y.toFixed(1)} L ${x.toFixed(1)} ${(y + c).toFixed(1)}
        L ${(x - c).toFixed(1)} ${y.toFixed(1)} Z"/>
      <text x="${(x + 12).toFixed(1)}" y="${(y - 8).toFixed(1)}">${echapper(l.nom)}</text>
    </g>`;
  }).join('');

  boite.innerHTML =
    `<svg viewBox="0 0 ${p.L} ${p.H}" preserveAspectRatio="xMidYMid meet" role="img"
          aria-label="Carte des revendeurs et des livreurs du réseau">${trame}${marqueurs}${mobiles}</svg>`;

  for (const g of boite.querySelectorAll('.lv')) {
    const choisir = () => {
      railActif = 'livreurs';
      for (const o of document.querySelectorAll('.rail-onglet')) {
        o.classList.toggle('est-actif', o.dataset.rail === 'livreurs');
      }
      selection = { type: 'livreurs', id: g.dataset.id };
      tracerRail();
      tracerCarte();
      tracerTiroir();
    };
    g.addEventListener('click', choisir);
    g.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); choisir(); }
    });
  }

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

    boite.innerHTML = `
      <div class="tiroir-tete">
        <div>
          <h3>${echapper(b.nom)}</h3>
          <p>${echapper(b.commune ?? '')} · ${echapper(b.type_activite ?? '')}${
            b.gerant_nom ? ` · ${echapper(b.gerant_nom)}` : ''}${
            b.telephone ? ` · <a href="tel:+${echapper(b.telephone)}">${echapper(telephoneLisible(b.telephone))}</a>` : ''}</p>
        </div>
        <div class="tiroir-actions">
          <button type="button" class="bouton" id="actionAttribuerBoutique">Rattacher à un distributeur</button>
        </div>
      </div>
      <div class="tiroir-faits">
        <div><small>Desservie par</small><span>${b.distributeurs
          ? echapper(b.distributeurs)
          : '<span class="etat etat--alerte">Personne</span>'}</span></div>
        <div><small>Marques</small><span>${echapper(b.marques ?? '—')}</span></div>
        <div><small>Demandes en cours</small><strong${
          Number(b.ruptures_ouvertes ?? 0) > 0 ? ' data-ton="alerte"' : ''
        }>${nombre(b.ruptures_ouvertes ?? 0)}</strong></div>
        <div><small>Recensée par</small><span>${echapper(b.agent_recenseur ?? '—')}</span></div>
      </div>`;

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
          <button type="button" class="bouton" id="actionAttribuerDist">Lui attribuer un revendeur</button>
        </div>
      </div>
      <div class="tiroir-faits">
        <div><small>Revendeurs</small><strong${boutiques === 0 ? ' data-ton="alerte"' : ''}>${nombre(boutiques)}</strong></div>
        <div><small>Livreurs actifs</small><strong${livreurs === 0 ? ' data-ton="alerte"' : ''}>${nombre(livreurs)}</strong></div>
        <div><small>En ligne</small><strong>${nombre(d.livreurs_en_ligne ?? 0)}</strong></div>
        <div><small>Demandes à livrer</small><strong${
          Number(d.courses_en_attente ?? 0) > 0 ? ' data-ton="alerte"' : ''
        }>${nombre(d.courses_en_attente ?? 0)}</strong></div>
        <div><small>Auto-distribution</small><span>${d.auto_distribution ? 'Oui' : 'Non'}</span></div>
      </div>
      ${boutiques === 0 ? `<p class="note" style="margin:0">
        Ce distributeur ne voit aucun revendeur, et <b>il ne peut pas en ajouter
        lui-même</b> : sa politique ne lui montre que les communes où il opère
        déjà, et il n'en a aucune. Son premier revendeur doit lui être attribué
        ici, sans quoi il ne commencera jamais.</p>` : ''}
      ${boutiques > 0 && livreurs === 0 ? `<p class="note" style="margin:0">
        Il reçoit des demandes et <b>ne peut les affecter à personne</b>. C'est à
        lui d'enrôler un livreur depuis l'application, onglet Flotte : le compte
        se remet en main propre.</p>` : ''}`;

    document.getElementById('actionAttribuerDist')
      .addEventListener('click', () => ouvrirAttribution(null, null, d.distributeur_id, d.nom));
    return;
  }

  if (selection.type === 'livreurs') {
    const l = etat.livreurs.find((x) => x.livreur_id === selection.id);
    if (!l) { selection = null; return tracerTiroir(); }

    const e = etatLivreur(l);
    const age = Number(l.position_age_secondes ?? NaN);
    boite.innerHTML = `
      <div class="tiroir-tete">
        <div>
          <h3>${echapper(l.nom)}</h3>
          <p>${echapper(l.distributeur ?? 'Sans flotte')}${
            l.marque ? ` · ${echapper(l.marque)}` : ''}${
            l.telephone ? ` · <a href="tel:+${echapper(l.telephone)}">${
              echapper(telephoneLisible(l.telephone))}</a>` : ''}</p>
        </div>
        <div class="tiroir-actions">
          <span class="etat etat--${e.cle === 'ok' || e.cle === 'course' ? 'ok' : 'dort'}">${e.texte}</span>
        </div>
      </div>
      <div class="tiroir-faits">
        <div><small>Livraisons en cours</small><strong>${nombre(l.courses_en_cours ?? 0)}</strong></div>
        <div><small>Livraisons terminées</small><strong>${nombre(l.livraisons_terminees ?? 0)}</strong></div>
        <div><small>Commune approchée</small><span>${echapper(l.commune_approchee ?? '—')}</span></div>
        <div><small>Dernière position</small><strong${
          !Number.isFinite(age) || age > 300 ? ' data-ton="alerte"' : ''
        }>${Number.isFinite(age) ? duree(age) : 'jamais'}</strong></div>
      </div>
      ${!Number.isFinite(age) || age > 300 ? `<p class="note" style="margin:0">
        Aucune position fraîche. <b>Sur Tecno, Infinix et itel, le système
        referme l'application dès l'écran éteint</b>, et le suivi s'arrête sans
        prévenir. Le réglage à faire est sur le téléphone du livreur, dans les
        économiseurs de batterie, et il ne peut pas être posé à distance.</p>` : ''}`;
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
      <div><small>Revendeurs concernés</small><strong${
        portee.length === 0 ? ' data-ton="alerte"' : ''}>${nombre(portee.length)}</strong></div>
      <div><small>Distributeurs affiliés</small><strong>${nombre(distributeurs.length)}</strong></div>
      <div><small>Demandes en cours</small><strong>${
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
      <b>Aucune inscription à valider</b>
      Les demandes d’accès déposées depuis le site apparaissent ici, et personne
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
  boutique_sans_distributeur: 'Revendeur sans distributeur',
  distributeur_sans_livreur: 'Distributeur sans livreur',
  rupture_sans_destinataire: 'Demande sans destinataire',
};

function tracerAnomalies() {
  const zone = document.getElementById('zoneAnomalies');

  if (!etat.anomalies.length) {
    zone.innerHTML = `<div class="vide">
      <b>Rien à signaler</b>
      Chaque revendeur actif a son distributeur, chaque distributeur a son
      livreur, et chaque demande a un destinataire.
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
      `Vers ${distributeurNom}. Choisissez le revendeur à lui rattacher.`;
    selBoutique.disabled = false;
    selBoutique.innerHTML = etat.boutiques.map((b) =>
      `<option value="${echapper(b.point_de_vente_id)}">${echapper(b.nom)} · ${
        echapper(b.commune ?? '')}${b.distributeurs
        ? ` (chez ${echapper(b.distributeurs)})` : ' (libre)'}</option>`).join('');
  } else {
    document.getElementById('sousTitreAttribution').textContent =
      `${boutiqueNom}. Choisissez le distributeur qui le desservira.`;
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
    retour.textContent = 'Il manque le revendeur, la marque ou le distributeur.';
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
        : `${resultat.boutique} est rattaché à ${resultat.distributeur} pour ${resultat.marque}.`,
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

/* ══ Le bandeau du tableau de bord ════════════════════════ */

function tracerBandeau() {
  const r = etat.reseau;
  const jours = etat.activite;
  const aujourdhui = jours.length ? jours[jours.length - 1] : null;
  const hier = jours.length > 1 ? jours[jours.length - 2] : null;

  // Le montant du jour comparé à celui d'hier. La comparaison est affichée
  // seulement quand hier valait quelque chose : « +infini par rapport à zéro »
  // n'apprend rien.
  const duJour = Number(aujourdhui?.montant ?? 0);
  const deHier = Number(hier?.montant ?? 0);
  const ecart = deHier > 0 ? Math.round(((duJour - deHier) / deHier) * 100) : null;

  const volume = document.getElementById('chiffreVolume');
  volume.textContent = montant(duJour);
  volume.title = montantExact(duJour);
  document.getElementById('detailVolume').innerHTML =
    `<span>${nombre(aujourdhui?.livraisons ?? 0)} livraison(s)</span>`
    + (ecart === null
      ? '<span style="opacity:.7">pas de comparaison, hier était à zéro</span>'
      : `<span class="evolution" data-sens="${ecart > 0 ? 'hausse' : ecart < 0 ? 'baisse' : 'stable'}">${
        ecart > 0 ? '+' : ''}${ecart} %</span><span style="opacity:.7">vs hier</span>`);

  document.getElementById('chiffrePoints').textContent = nombre(r.boutiques_actives);
  document.getElementById('detailPoints').innerHTML =
    `<span>${nombre(r.boutiques_total)} recensé(s)</span>`
    + `<span>${nombre(r.distributeurs)} distributeur(s)</span>`;

  document.getElementById('chiffreRuptures').textContent = nombre(r.ruptures_ouvertes);
  const sansPreneur = etat.rupturesRecentes.filter(
    (x) => x.statut === 'signalee' && !x.distributeur).length;
  document.getElementById('detailRuptures').innerHTML =
    `<span><b>${nombre(sansPreneur)}</b> sans destinataire</span>`
    + `<span>${nombre(r.ruptures_a_confirmer)} à confirmer</span>`;

  const enCourse = etat.livreurs.filter((l) => Number(l.courses_en_cours ?? 0) > 0).length;
  document.getElementById('chiffreLivreurs').textContent = nombre(enCourse);
  document.getElementById('detailLivreurs').innerHTML =
    `<span>sur ${nombre(r.livreurs_actifs)} actif(s)</span>`
    + `<span>${nombre(r.livreurs_en_ligne)} en ligne</span>`;
}

/* ── Les ruptures récentes ────────────────────────────────── */

function tracerRupturesRecentes() {
  const boite = document.getElementById('demandesRecentesListe');

  if (!etat.rupturesRecentes.length) {
    boite.innerHTML = '<div class="vide" style="border:0;padding:12px 0">'
      + 'Aucune demande en cours. Tous les revendeurs du réseau sont servis.</div>';
    return;
  }

  // La plus récente d'abord : ce n'est pas la même liste que « Demandes en
  // cours » (triée par urgence), même source, lecture différente.
  const ordonnees = [...etat.rupturesRecentes]
    .sort((a, b) => Number(a.attente_secondes ?? 0) - Number(b.attente_secondes ?? 0))
    .slice(0, 8);

  boite.innerHTML = ordonnees.map((r) => {
    const attente = Number(r.attente_secondes ?? 0);
    const pris = r.statut === 'prise_en_charge';
    const point = pris ? 'done' : r.confirmee_le ? 'route' : '';
    return `<div class="event-item">
      <span class="event-dot ${point}"></span>
      <div class="event-main">
        <strong>${echapper(r.produit)} · ${echapper(r.point_de_vente)}</strong>
        <span>${echapper(r.commune ?? '')}${r.distributeur ? ` · ${echapper(r.distributeur)}` : ''}</span>
      </div>
      <div class="event-value">${duree(attente)}<small>${pris ? 'Prise en charge' : r.confirmee_le ? 'En attente' : 'À confirmer'}</small></div>
    </div>`;
  }).join('');
}

/* Durée courte, dans la forme utilisée partout ailleurs dans le produit. */
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

/* ══ Carte : livreurs et communes ═════════════════════════ */

/* L'état d'un livreur, dans l'ordre où il compte pour qui pilote.
   `en_ligne` ne suffit pas : un téléphone endormi par Android laisse le
   drapeau allumé sans plus rien remonter, et le distributeur affecte alors
   une course à quelqu'un qui ne la verra jamais. */
function etatLivreur(l) {
  if (l.actif !== true) return { cle: 'dort', texte: 'Écarté' };
  if (Number(l.courses_en_cours ?? 0) > 0) return { cle: 'course', texte: 'En course' };
  if (l.en_ligne !== true) return { cle: 'dort', texte: 'Hors ligne' };
  const age = Number(l.position_age_secondes ?? Infinity);
  if (!Number.isFinite(age) || age > 300) return { cle: 'dort', texte: 'Position figée' };
  return { cle: 'ok', texte: 'Disponible' };
}

function tracerTableLivreurs() {
  const table = document.getElementById('tableLivreurs');

  if (!etat.livreurs.length) {
    table.innerHTML = '<tbody><tr><td style="color:rgba(8,22,14,.5)">'
      + 'Aucun livreur enrôlé. C\'est au distributeur de le faire, depuis '
      + 'l\'application, onglet Flotte.</td></tr></tbody>';
    return;
  }

  table.innerHTML = `
    <thead><tr>
      <th>Livreur</th><th>Distributeur</th><th>Commune</th><th>État</th>
    </tr></thead>
    <tbody>${etat.livreurs.map((l) => {
      const e = etatLivreur(l);
      const classe = e.cle === 'ok' || e.cle === 'course' ? 'ok' : 'dort';
      return `<tr>
        <td>${echapper(l.nom)}<small>${echapper(telephoneLisible(l.telephone))}</small></td>
        <td>${echapper(l.distributeur ?? '—')}<small>${echapper(l.marque ?? 'Indépendant')}</small></td>
        <td>${echapper(l.commune_approchee ?? '—')}</td>
        <td><span class="etat etat--${classe}">${e.texte}</span></td>
      </tr>`;
    }).join('')}</tbody>`;
}

function tracerTableCommunes() {
  const table = document.getElementById('tableCommunes');

  if (!etat.communes.length) {
    table.innerHTML = '<tbody><tr><td style="color:rgba(8,22,14,.5)">'
      + 'Aucune commune couverte.</td></tr></tbody>';
    return;
  }

  const ordonnees = [...etat.communes].sort((a, b) => Number(b.points) - Number(a.points));

  table.innerHTML = `
    <thead><tr>
      <th>Commune</th><th class="num">Revendeurs</th>
      <th class="num">Sans distributeur</th><th class="num">Demandes</th>
    </tr></thead>
    <tbody>${ordonnees.map((c) => {
      const orphelines = Number(c.points_sans_distributeur ?? 0);
      return `<tr>
        <td>${echapper(c.commune ?? '—')}</td>
        <td class="num">${nombre(c.points)}</td>
        <td class="num"${orphelines > 0 ? ' style="color:#D65C52;font-weight:600"' : ''}>${nombre(orphelines)}</td>
        <td class="num">${nombre(c.ruptures)}</td>
      </tr>`;
    }).join('')}</tbody>`;
}

function remplirCommunes() {
  const communes = [...new Set(etat.boutiques.map((b) => b.commune).filter(Boolean))].sort();
  const options = communes.map((c) =>
    `<option value="${echapper(c)}">${echapper(c)}</option>`).join('');

  const filtre = document.getElementById('filtreCommune');
  const choix = filtre.value;
  filtre.innerHTML = `<option value="">Toutes communes</option>${options}`;
  filtre.value = communes.includes(choix) ? choix : '';

  const diffusion = document.getElementById('diffusionCommune');
  const choixDiffusion = diffusion.value;
  diffusion.innerHTML = `<option value="">Partout</option>${options}`;
  diffusion.value = communes.includes(choixDiffusion) ? choixDiffusion : '';

  const tableau = document.getElementById('filtreCommuneTableau');
  const choixTableau = tableau.value;
  tableau.innerHTML = `<option value="">Toutes les communes</option>${options}`;
  tableau.value = communes.includes(choixTableau) ? choixTableau : '';
}

document.getElementById('filtreCommuneTableau').addEventListener('change', (e) => {
  filtreCommuneTableau = e.target.value;
  tracerCouverture();
});

// Purement visuel, comme dans le prototype : le rythme affiché reste celui
// des quatorze derniers jours, aucune vue serveur ne recalcule encore un
// autre pas de temps.
for (const bouton of document.querySelectorAll('.periods button')) {
  bouton.addEventListener('click', () => {
    for (const b of document.querySelectorAll('.periods button')) b.classList.remove('selected');
    bouton.classList.add('selected');
  });
}

document.getElementById('filtreCommune').addEventListener('change', (e) => {
  filtreCommune = e.target.value;
  selection = null;
  tracerCarte();
  tracerTiroir();
});

/* ══ Acteurs ══════════════════════════════════════════════ */

function tracerActeurs() {
  const a = etat.acteurs;
  const cartes = [
    ['Revendeurs', a.points_de_vente, a.points_retires, 'retiré(s)'],
    ['Fabricants', a.fabricants, a.fabricants_suspendus, 'suspendu(s)'],
    ['Distributeurs', a.distributeurs, a.distributeurs_suspendus, 'suspendu(s)'],
    ['Livreurs', a.livreurs, a.livreurs_ecartes, 'écarté(s)'],
    ['Agents recenseurs', a.agents_recenseurs, 0, ''],
  ];

  document.getElementById('grilleActeurs').innerHTML = cartes.map(
    ([nom, actifs, inactifs, mot]) => `<article class="carte c3">
      <header><h3>${echapper(nom)}</h3></header>
      <div class="chiffre">${nombre(actifs ?? 0)}</div>
      <div class="chiffre-suite">${Number(inactifs ?? 0) > 0
        ? `<span><b>${nombre(inactifs)}</b> ${echapper(mot)}</span>`
        : '<span style="opacity:.6">aucun retrait</span>'}</div>
    </article>`).join('');
}

function tracerAttribution() {
  const table = document.getElementById('tableAttribution');

  if (!etat.attribution.length) {
    table.innerHTML = '<tbody><tr><td style="color:rgba(8,22,14,.5)">'
      + 'Aucune marque enregistrée.</td></tr></tbody>';
    return;
  }

  table.innerHTML = `
    <thead><tr>
      <th>Marque</th><th class="num">Revendeurs rattachés</th>
      <th class="num">Distributeurs</th><th>Périmètre</th>
    </tr></thead>
    <tbody>${etat.attribution.map((a) => {
      const points = Number(a.points_attribues ?? 0);
      return `<tr>
        <td>${echapper(a.fabricant_nom)}</td>
        <td class="num"${points === 0 ? ' style="color:#D65C52;font-weight:600"' : ''}>${nombre(points)}</td>
        <td class="num">${nombre(a.distributeurs ?? 0)}</td>
        <td style="white-space:normal">${a.perimetre
          ? echapper(a.perimetre)
          : '<span class="etat etat--alerte">Aucun revendeur</span>'}</td>
      </tr>`;
    }).join('')}</tbody>`;
}

/* Le retrait d'un acteur. Un seul tableau pour quatre natures d'objets, parce
   que le geste est le même : « celui-là ne travaille plus ». */
function tracerTableActeurs() {
  const table = document.getElementById('tableActeurs');

  const lignes = [
    ...etat.boutiques.map((b) => ({
      type: 'point_de_vente', id: b.point_de_vente_id, nom: b.nom,
      detail: `${b.commune ?? ''} · revendeur`, actif: b.statut === 'actif',
    })),
    ...etat.distributeurs.map((d) => ({
      type: 'distributeur', id: d.distributeur_id, nom: d.nom,
      detail: d.fabricant_rattache ? `Affilié · ${d.fabricant_rattache}` : 'Distributeur indépendant',
      actif: d.statut === 'actif',
    })),
    ...etat.livreurs.map((l) => ({
      type: 'livreur', id: l.livreur_id, nom: l.nom,
      detail: `Livreur · ${l.distributeur ?? 'sans flotte'}`, actif: l.actif === true,
    })),
  ];

  if (!lignes.length) {
    table.innerHTML = '<tbody><tr><td style="color:rgba(8,22,14,.5)">'
      + 'Le réseau est vide.</td></tr></tbody>';
    return;
  }

  // Les retirés en tête : ce sont eux qu'on vient chercher dans ce tableau,
  // pour décider s'ils reviennent.
  lignes.sort((a, b) => (a.actif === b.actif ? a.nom.localeCompare(b.nom) : a.actif ? 1 : -1));

  table.innerHTML = `
    <thead><tr><th>Acteur</th><th>Nature</th><th>État</th><th></th></tr></thead>
    <tbody>${lignes.map((l) => `<tr>
      <td>${echapper(l.nom)}<small>${echapper(l.detail)}</small></td>
      <td>${echapper({ point_de_vente: 'Revendeur', distributeur: 'Distributeur',
        livreur: 'Livreur' }[l.type])}</td>
      <td>${l.actif
        ? '<span class="etat etat--ok">En service</span>'
        : '<span class="etat etat--dort">Retiré</span>'}</td>
      <td style="text-align:end">
        <button type="button" class="bouton ${l.actif ? 'bouton--danger' : 'bouton--creux'}"
                data-acteur="${echapper(l.type)}" data-id="${echapper(l.id)}"
                data-nom="${echapper(l.nom)}" data-actif="${l.actif}">${
          l.actif ? 'Retirer' : 'Réactiver'}</button>
      </td>
    </tr>`).join('')}</tbody>`;

  for (const bouton of table.querySelectorAll('[data-acteur]')) {
    bouton.addEventListener('click', () => basculerActeur(bouton.dataset));
  }
}

async function basculerActeur({ acteur, id, nom, actif }) {
  const retirer = actif === 'true';

  if (retirer && !confirm(
    `Retirer ${nom} du réseau ?\n\n`
    + 'Rien n\'est effacé : son historique reste, et vous pouvez le réactiver '
    + 'à tout moment. Il cesse simplement d\'apparaître dans le réseau actif.',
  )) return;

  try {
    const r = await interroger('rpc/changer_statut_acteur', {
      method: 'POST',
      body: JSON.stringify({ p_type: acteur, p_id: id, p_actif: !retirer }),
    });
    informer(`${r.nom} ${retirer ? 'est retiré du réseau' : 'est de nouveau en service'}.`,
      'succes');
    await rafraichir();
  } catch (erreur) {
    if (erreur.message === 'session') return;
    informer(erreur.message, 'erreur');
  }
}

/* ══ Diffusion ════════════════════════════════════════════ */

const TYPES_DIFFUSION = {
  notification: 'Notification',
  splash_publicitaire: 'Splash',
  sondage: 'Sondage',
};

const CIBLES = {
  reseau_complet: 'Réseau complet',
  points_de_vente: 'Points de vente',
  distributeurs: 'Distributeurs',
  fabricants: 'Fabricants',
  livreurs: 'Livreurs',
};

document.getElementById('diffusionType').addEventListener('change', (e) => {
  document.getElementById('champOptions').hidden = e.target.value !== 'sondage';
});

/* La portée s'annonce AVANT l'envoi, pas après. Une diffusion ne se rattrape
   pas : savoir qu'on s'adresse à quatre cents boutiques change ce qu'on écrit,
   et parfois la décision d'envoyer. */
function estimerPortee() {
  const cible = document.getElementById('diffusionCible').value;
  const commune = document.getElementById('diffusionCommune').value;

  const boutiques = etat.boutiques.filter(
    (b) => b.statut === 'actif' && (!commune || b.commune === commune));
  const compte = {
    points_de_vente: boutiques.length,
    fabricants: etat.marques.length,
    distributeurs: etat.distributeurs.filter((d) => d.statut === 'actif').length,
    livreurs: etat.livreurs.filter((l) => l.actif === true).length,
  };
  const portee = cible === 'reseau_complet'
    ? Object.values(compte).reduce((s, n) => s + n, 0)
    : compte[cible] ?? 0;

  document.getElementById('porteeEstimee').textContent = portee === 0
    ? 'Aucun destinataire ne correspond.'
    : `${portee} destinataire(s)${commune ? ` à ${commune}` : ''}.`;
}

for (const id of ['diffusionCible', 'diffusionCommune']) {
  document.getElementById(id).addEventListener('change', estimerPortee);
}

document.getElementById('diffusionVisuel').addEventListener('change', (event) => {
  const fichier = event.target.files[0];
  const apercu = document.getElementById('apercuDiffusionVisuel');
  if (!fichier) {
    apercu.hidden = true;
    apercu.removeAttribute('src');
    return;
  }
  if (fichier.size > 5 * 1024 * 1024) {
    event.target.value = '';
    apercu.hidden = true;
    informer('Le visuel dépasse 5 Mo.', 'erreur');
    return;
  }
  apercu.src = URL.createObjectURL(fichier);
  apercu.hidden = false;
});

async function televerserVisuel(fichier) {
  if (!fichier) return null;
  const extension = fichier.name.split('.').pop().toLowerCase();
  const chemin = `${crypto.randomUUID()}.${extension}`;
  const reponse = await fetch(`${URL_BASE}/storage/v1/object/notifications/${chemin}`, {
    method: 'POST',
    headers: {
      apikey: CLE,
      Authorization: `Bearer ${jeton}`,
      'Content-Type': fichier.type,
      'x-upsert': 'false',
    },
    body: fichier,
  });
  if (!reponse.ok) throw new Error('Le visuel n’a pas pu être téléversé.');
  return `${URL_BASE}/storage/v1/object/public/notifications/${chemin}`;
}

document.getElementById('boutonDiffuser').addEventListener('click', async () => {
  const bouton = document.getElementById('boutonDiffuser');
  const retour = document.getElementById('messageDiffusion');

  const type = document.getElementById('diffusionType').value;
  const cible = document.getElementById('diffusionCible').value;
  const commune = document.getElementById('diffusionCommune').value || null;
  const titre = document.getElementById('diffusionTitre').value.trim();
  const message = document.getElementById('diffusionMessage').value.trim();
  const fichier = document.getElementById('diffusionVisuel').files[0] || null;
  const options = document.getElementById('diffusionOptions').value
    .split('\n').map((s) => s.trim()).filter(Boolean);

  const dire = (texte, ton) => {
    retour.textContent = texte;
    retour.dataset.ton = ton;
    retour.hidden = false;
  };

  if (titre.length < 3) return dire('Donnez un objet à cette diffusion.', 'erreur');
  if (message.length < 3) return dire('Le message est vide.', 'erreur');
  if (type === 'sondage' && options.length < 2) {
    return dire('Un sondage demande au moins deux réponses possibles, une par ligne.', 'erreur');
  }

  const portee = document.getElementById('porteeEstimee').textContent;
  if (!confirm(`Diffuser « ${titre} » ?\n\n${portee}\n\n`
    + 'Une diffusion ne se rattrape pas.')) return;

  bouton.disabled = true;
  bouton.textContent = 'Envoi…';

  try {
    const visuelUrl = await televerserVisuel(fichier);
    const r = await interroger('rpc/diffuser_notification', {
      method: 'POST',
      body: JSON.stringify({
        p_type: type,
        p_titre: titre,
        p_message: message,
        p_cible: cible,
        p_commune: commune,
        p_options: type === 'sondage' ? options : null,
        p_visuel_url: visuelUrl,
      }),
    });

    document.getElementById('diffusionTitre').value = '';
    document.getElementById('diffusionMessage').value = '';
    document.getElementById('diffusionOptions').value = '';
    document.getElementById('diffusionVisuel').value = '';
    document.getElementById('apercuDiffusionVisuel').hidden = true;
    retour.hidden = true;
    informer(`Diffusion envoyée à ${r.portee} destinataire(s).`, 'succes');
    await rafraichir();
  } catch (erreur) {
    if (erreur.message === 'session') return;
    dire(erreur.message, 'erreur');
  } finally {
    bouton.disabled = false;
    bouton.textContent = 'Diffuser';
  }
});

function tracerDiffusions() {
  const table = document.getElementById('tableDiffusions');

  if (!etat.diffusions.length) {
    table.innerHTML = '<tbody><tr><td style="color:rgba(8,22,14,.5)">'
      + 'Aucune diffusion émise.</td></tr></tbody>';
    return;
  }

  table.innerHTML = `
    <thead><tr>
      <th>Objet</th><th>Type</th><th>Cible</th>
      <th class="num">Portée</th><th class="num">Réponses</th><th>Envoyée</th>
    </tr></thead>
    <tbody>${etat.diffusions.map((d) => {
      const sondage = d.type === 'sondage';
      const portee = Number(d.portee ?? 0);
      const reponses = Number(d.reponses ?? 0);
      const taux = sondage && portee > 0 ? Math.round((reponses / portee) * 100) : null;
      const envoi = new Date(d.date_envoi);
      return `<tr>
        <td>${echapper(d.titre)}<small style="white-space:normal">${echapper(d.message)}</small></td>
        <td>${echapper(TYPES_DIFFUSION[d.type] ?? d.type)}</td>
        <td>${echapper(CIBLES[d.cible] ?? d.cible)}${
          d.commune ? `<small>${echapper(d.commune)}</small>` : ''}</td>
        <td class="num">${nombre(portee)}</td>
        <td class="num">${sondage
          ? `${nombre(reponses)}${taux === null ? '' : ` <span style="opacity:.6">(${taux} %)</span>`}`
          : '<span style="opacity:.45" title="Aucun accusé de lecture n’existe dans le schéma">non suivi</span>'}</td>
        <td><small>${envoi.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' })}
          ${envoi.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}</small></td>
      </tr>`;
    }).join('')}</tbody>`;
}

/* ══ Communications à valider ════════════════════════════ */

function tracerSoumissions() {
  const zone = document.getElementById('zoneApprobations');
  const soumissions = [...etat.soumissions]
    .sort((a, b) => new Date(a.cree_le) - new Date(b.cree_le));

  if (!soumissions.length) {
    zone.innerHTML = `<div class="vide">
      <b>Aucune communication en attente</b>
      Les contenus soumis par les marques et distributeurs apparaîtront ici avant toute publication.
    </div>`;
    return;
  }

  zone.innerHTML = `<div class="approbations">${soumissions.map((s) => {
    const date = new Date(s.cree_le);
    const dateLisible = Number.isNaN(date.getTime()) ? 'Date inconnue'
      : `${date.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit', year: 'numeric' })} à ${date.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}`;
    return `<article class="approbation">
      <div class="approbation-contenu">
        <div class="approbation-tete">
          <h4>${echapper(s.titre)}</h4>
          <span class="etat etat--dort">${echapper(TYPES_DIFFUSION[s.type] ?? s.type)}</span>
        </div>
        <p class="approbation-message">${echapper(s.message)}</p>
        <p class="approbation-meta">
          <strong>${echapper(s.organisation ?? s.emetteur ?? 'Organisation inconnue')}</strong>
          · ${echapper(s.role_emetteur ?? 'Compte professionnel')}
          · Soumise le ${echapper(dateLisible)}${s.commune ? ` · ${echapper(s.commune)}` : ''}
        </p>
      </div>
      <div class="approbation-actions">
        ${s.visuel_url ? `<button type="button" class="bouton bouton--creux"
          data-apercu="${echapper(s.diffusion_id)}">Voir le visuel</button>` : ''}
        <button type="button" class="bouton bouton--danger"
          data-refuser-communication="${echapper(s.diffusion_id)}"
          data-titre="${echapper(s.titre)}">Refuser</button>
        <button type="button" class="bouton"
          data-approuver-communication="${echapper(s.diffusion_id)}"
          data-titre="${echapper(s.titre)}">Approuver et publier</button>
      </div>
    </article>`;
  }).join('')}</div>`;

  for (const bouton of zone.querySelectorAll('[data-approuver-communication]')) {
    bouton.addEventListener('click', () => approuverCommunication(bouton.dataset));
  }
  for (const bouton of zone.querySelectorAll('[data-refuser-communication]')) {
    bouton.addEventListener('click', () => refuserCommunication(bouton.dataset));
  }
  for (const bouton of zone.querySelectorAll('[data-apercu]')) {
    bouton.addEventListener('click', () => ouvrirApercuCommunication(
      soumissions.find((s) => s.diffusion_id === bouton.dataset.apercu)));
  }
}

async function approuverCommunication({ approuverCommunication: id, titre }) {
  if (!confirm(`Approuver et publier « ${titre} » auprès des points de vente ?`)) return;
  try {
    const publiee = await interroger('rpc/valider_communication', {
      method: 'POST',
      body: JSON.stringify({ p_diffusion_id: id }),
    });
    if (!publiee) throw new Error('Cette communication a déjà été traitée.');
    informer(`« ${titre} » est approuvée et publiée.`, 'succes');
    await rafraichir();
  } catch (erreur) {
    if (erreur.message === 'session') return;
    informer(erreur.message, 'erreur');
  }
}

async function refuserCommunication({ refuserCommunication: id, titre }) {
  const motif = prompt(`Refuser « ${titre} » ?\n\nMotif, conservé pour le suivi interne.`);
  if (motif === null) return;
  try {
    const refusee = await interroger('rpc/refuser_communication', {
      method: 'POST',
      body: JSON.stringify({ p_diffusion_id: id, p_motif: motif.trim() || null }),
    });
    if (!refusee) throw new Error('Cette communication a déjà été traitée.');
    informer(`« ${titre} » a été refusée.`, 'succes');
    await rafraichir();
  } catch (erreur) {
    if (erreur.message === 'session') return;
    informer(erreur.message, 'erreur');
  }
}

async function ouvrirApercuCommunication(soumission) {
  if (!soumission) return;
  const fenetre = document.getElementById('fenetreApercuCommunication');
  const image = document.getElementById('imageApercuCommunication');
  const statut = document.getElementById('statutApercuCommunication');
  document.getElementById('titreApercuCommunication').textContent = soumission.titre;
  document.getElementById('texteApercuCommunication').textContent = soumission.message;
  image.hidden = true;
  image.removeAttribute('src');
  statut.textContent = 'Chargement du visuel privé…';
  fenetre.showModal();

  try {
    const chemin = String(soumission.visuel_url).replace(/^\/+/, '');
    if (chemin.split('/').some((segment) => segment === '..')) {
      throw new Error('Chemin de visuel invalide.');
    }
    const objet = chemin.split('/').map(encodeURIComponent).join('/');
    const reponse = await fetch(`${URL_BASE}/storage/v1/object/sign/notifications-brouillons/${objet}`, {
      method: 'POST',
      headers: {
        apikey: CLE,
        Authorization: `Bearer ${jeton}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ expiresIn: 300 }),
    });
    const corps = await reponse.json().catch(() => ({}));
    if (!reponse.ok || !corps.signedURL) throw new Error('Le visuel privé ne peut pas être chargé.');
    const url = corps.signedURL.startsWith('http') ? corps.signedURL
      : `${URL_BASE}/storage/v1${corps.signedURL.startsWith('/') ? '' : '/'}${corps.signedURL}`;
    image.src = url;
    image.hidden = false;
    statut.textContent = 'Aperçu temporaire, réservé à cette session.';
  } catch (erreur) {
    if (erreur.message === 'session') return;
    statut.textContent = erreur.message;
  }
}

/* ══ Statistiques ═════════════════════════════════════════ */

function tracerSemaines() {
  const boite = document.getElementById('grapheSemaines');
  const pied = document.getElementById('piedSemaines');
  const semaines = etat.semaines;

  if (!semaines.length) {
    boite.innerHTML = '<div class="vide" style="border:0;padding:20px 0">Pas encore de données.</div>';
    pied.textContent = '';
    return;
  }

  const L = 900;
  const H = 230;
  const margeG = 56;
  const margeD = 14;
  const margeH = 16;
  const margeB = 36;
  const larg = L - margeG - margeD;
  const haut = H - margeH - margeB;

  const maxi = Math.max(1, ...semaines.map((s) => Number(s.montant)));
  const plafond = Math.max(1000, Math.ceil(maxi / 1000) * 1000);
  const pas = larg / semaines.length;
  const y = (v) => margeH + haut - (v / plafond) * haut;

  const grilles = [0, plafond / 2, plafond].map((v) =>
    `<line x1="${margeG}" y1="${y(v).toFixed(1)}" x2="${L - margeD}" y2="${y(v).toFixed(1)}" class="graphe-grille"/>`
    + `<text x="${margeG - 8}" y="${(y(v) + 3.5).toFixed(1)}" text-anchor="end" class="graphe-axe">${montant(v)}</text>`).join('');

  const barres = semaines.map((s, i) => {
    const v = Number(s.montant);
    const x = margeG + i * pas + pas * 0.2;
    const l = pas * 0.6;
    return `<rect x="${x.toFixed(1)}" y="${y(v).toFixed(1)}" width="${l.toFixed(1)}"
      height="${Math.max(0, (v / plafond) * haut).toFixed(1)}" rx="2.5" fill="${VERT_SOMBRE}">
      <title>${montantExact(v)} · ${s.livraisons} livraison(s)</title></rect>`;
  }).join('');

  const etiquettes = semaines.map((s, i) => {
    if (i % 2 !== 0 && i !== semaines.length - 1) return '';
    const d = new Date(`${s.semaine}T00:00:00`);
    return `<text x="${(margeG + i * pas + pas / 2).toFixed(1)}" y="${H - 14}"
      text-anchor="middle" class="graphe-axe">${String(d.getDate()).padStart(2, '0')}/${
      String(d.getMonth() + 1).padStart(2, '0')}</text>`;
  }).join('');

  boite.innerHTML = `<svg viewBox="0 0 ${L} ${H}" role="img"
    aria-label="Volume livré par semaine sur douze semaines">${grilles}${barres}${etiquettes}</svg>`;

  const total = semaines.reduce((s, x) => s + Number(x.montant), 0);
  const livraisons = semaines.reduce((s, x) => s + Number(x.livraisons), 0);
  pied.textContent = total === 0
    ? 'Aucune livraison terminée sur la période. Le volume se remplit au fur et à mesure du terrain.'
    : `${montantExact(total)} sur douze semaines, en ${nombre(livraisons)} livraison(s).`;
}

function tracerParFabricant() {
  const table = document.getElementById('tableParFabricant');

  if (!etat.parFabricant.length) {
    table.innerHTML = '<tbody><tr><td style="color:rgba(8,22,14,.5)">'
      + 'Aucune marque enregistrée.</td></tr></tbody>';
    return;
  }

  const ordonnees = [...etat.parFabricant]
    .sort((a, b) => Number(b.chiffre_affaires ?? 0) - Number(a.chiffre_affaires ?? 0));

  table.innerHTML = `
    <thead><tr>
      <th>Marque</th><th class="num">Volume livré</th><th class="num">Livraisons</th>
      <th class="num">Taux de service</th><th class="num">Évolution</th>
    </tr></thead>
    <tbody>${ordonnees.map((f) => {
      const recent = Number(f.montant_30j ?? 0);
      const avant = Number(f.montant_30j_precedents ?? 0);
      // Sans période de référence, il n'y a pas d'évolution à afficher. Un
      // « +100 % » parti de zéro est un chiffre qui ne veut rien dire.
      const ecart = avant > 0 ? Math.round(((recent - avant) / avant) * 100) : null;
      const taux = f.taux_de_service_pct;
      return `<tr>
        <td>${echapper(f.fabricant_nom)}</td>
        <td class="num" title="${montantExact(f.chiffre_affaires)}">${montant(f.chiffre_affaires)}</td>
        <td class="num">${nombre(f.nombre_livraisons ?? 0)}</td>
        <td class="num">${taux === null || taux === undefined ? '—' : `${taux} %`}</td>
        <td class="num">${ecart === null
          ? '<span style="opacity:.4" title="Aucune activité sur la période précédente">—</span>'
          : `<span class="evolution" data-sens="${ecart > 0 ? 'hausse' : ecart < 0 ? 'baisse' : 'stable'}">${
            ecart > 0 ? '+' : ''}${ecart} %</span>`}</td>
      </tr>`;
    }).join('')}</tbody>`;
}

function tracerProduitsTendus() {
  const table = document.getElementById('tableProduitsTendus');

  if (!etat.produitsTendus.length) {
    table.innerHTML = '<tbody><tr><td style="color:rgba(8,22,14,.5)">'
      + 'Aucune demande enregistrée à ce jour.</td></tr></tbody>';
    return;
  }

  const ordonnes = [...etat.produitsTendus]
    .sort((a, b) => Number(b.signalements) - Number(a.signalements))
    .slice(0, 10);
  const maxi = Math.max(1, ...ordonnes.map((p) => Number(p.signalements)));

  table.innerHTML = `
    <thead><tr>
      <th>Produit</th><th class="num">Demandes</th><th class="num">Revendeurs</th>
    </tr></thead>
    <tbody>${ordonnes.map((p) => {
      const n = Number(p.signalements);
      const intensite = 0.14 + (n / maxi) * 0.56;
      return `<tr>
        <td>${echapper(p.produit)}<small>${echapper(p.marque)}${
          p.reference ? ` · ${echapper(p.reference)}` : ''}</small></td>
        <td class="num"><span class="cellule-chaude"
          style="background:rgba(255,92,57,${intensite.toFixed(2)})">${nombre(n)}</span></td>
        <td class="num">${nombre(p.boutiques_touchees)}</td>
      </tr>`;
    }).join('')}</tbody>`;
}

/* ── Exports ──────────────────────────────────────────────
   CSV plutôt qu'un vrai fichier Excel : le cahier demande un export
   exploitable dans un tableur, et un .xlsx exigerait une bibliothèque de
   plusieurs centaines de kilo-octets pour le même résultat. Le point-virgule
   est le séparateur qu'attend Excel en configuration française, et le BOM lui
   fait lire l'UTF-8 correctement, faute de quoi tous les accents se cassent. */
function telechargerCsv(nom, entetes, lignes) {
  const echapperChamp = (v) => {
    const s = String(v ?? '');
    return /[";\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const contenu = '﻿'
    + [entetes, ...lignes].map((l) => l.map(echapperChamp).join(';')).join('\r\n');

  const lien = document.createElement('a');
  lien.href = URL.createObjectURL(new Blob([contenu], { type: 'text/csv;charset=utf-8' }));
  lien.download = `${nom}-${new Date().toISOString().slice(0, 10)}.csv`;
  lien.click();
  URL.revokeObjectURL(lien.href);
}

document.getElementById('exportCsv').addEventListener('click', () => {
  // Un seul fichier plutôt que trois : il s'ouvre une fois, et les trois
  // tableaux s'y lisent à la suite, séparés par leur titre.
  const lignes = [];

  lignes.push(['VOLUME LIVRÉ PAR SEMAINE']);
  lignes.push(['Semaine', 'Montant F CFA', 'Livraisons', 'Demandes reçues']);
  for (const s of etat.semaines) {
    lignes.push([s.semaine, Math.round(Number(s.montant)), s.livraisons, s.ruptures]);
  }

  lignes.push([]);
  lignes.push(['PAR MARQUE']);
  lignes.push(['Marque', 'Volume livré F CFA', 'Livraisons', 'Taux de service %',
    '30 derniers jours', '30 jours précédents']);
  for (const f of etat.parFabricant) {
    lignes.push([f.fabricant_nom, Math.round(Number(f.chiffre_affaires ?? 0)),
      f.nombre_livraisons ?? 0, f.taux_de_service_pct ?? '',
      Math.round(Number(f.montant_30j ?? 0)), Math.round(Number(f.montant_30j_precedents ?? 0))]);
  }

  lignes.push([]);
  lignes.push(['PRODUITS LES PLUS DEMANDÉS']);
  lignes.push(['Produit', 'Référence', 'Marque', 'Demandes', 'Revendeurs concernés',
    'Servies', 'Non servies']);
  for (const p of etat.produitsTendus) {
    lignes.push([p.produit, p.reference ?? '', p.marque, p.signalements,
      p.boutiques_touchees, p.servies, p.non_servies]);
  }

  telechargerCsv('yalla-statistiques', ['Statistiques Yalla', new Date().toLocaleString('fr-FR')], lignes);
});

/* Le PDF passe par l'impression du navigateur, et une feuille de style dédiée
   retire la coque d'exploitation. Embarquer un générateur de PDF coûterait
   plusieurs centaines de kilo-octets et obligerait à ouvrir `script-src` vers
   un hébergeur extérieur, pour un résultat que le navigateur produit déjà. */
document.getElementById('exportPdf').addEventListener('click', () => window.print());

/* ══ Chargement ═══════════════════════════════════════════ */

function tracerBadges() {
  const demandes = etat.demandes.filter((d) => d.statut === 'en_attente').length;
  const anomalies = etat.anomalies.length;
  const approbations = etat.soumissions.length;

  const bDemandes = document.getElementById('compteurDemandes');
  bDemandes.textContent = demandes;
  bDemandes.hidden = demandes === 0;
  bDemandes.dataset.urgent = demandes > 0 ? 'oui' : 'non';

  const bAnomalies = document.getElementById('compteurAnomalies');
  bAnomalies.textContent = anomalies;
  bAnomalies.hidden = anomalies === 0;
  bAnomalies.dataset.urgent = anomalies > 0 ? 'oui' : 'non';

  const bApprobations = document.getElementById('compteurApprobations');
  bApprobations.textContent = approbations;
  bApprobations.hidden = approbations === 0;
  bApprobations.dataset.urgent = approbations > 0 ? 'oui' : 'non';
}

/* Les quatorze lectures partent ensemble. En série, la page mettrait une
   dizaine de secondes à s'afficher sur une connexion d'Abidjan ; en parallèle,
   elle met le temps de la plus lente. */
const LECTURES = {
  reseau: 'v_supervision_reseau?select=*',
  demandes: 'v_demandes_acces?select=*&order=created_at.desc',
  anomalies: 'v_anomalies_reseau?select=*&order=type_anomalie,depuis',
  distributeurs: 'v_supervision_distributeurs?select=*&order=nom',
  boutiques: 'v_supervision_boutiques?select=*&order=commune,nom',
  // La table plutôt que la vue de tableau de bord du fabricant : on n'a besoin
  // que des noms pour remplir des sélecteurs, et cette vue-là est désormais
  // filtrée sur la ligne de l'appelant.
  marques: 'fabricants?select=fabricant_id:id,fabricant_nom:nom&statut=eq.actif&order=nom',
  activite: 'v_supervision_activite?select=*&order=jour',
  acteurs: 'v_supervision_acteurs?select=*',
  livreurs: 'v_supervision_livreurs?select=*&order=nom',
  communes: 'v_supervision_communes?select=*',
  rupturesRecentes: 'v_supervision_ruptures_recentes?select=*',
  attribution: 'v_supervision_attribution?select=*&order=fabricant_nom',
  semaines: 'v_supervision_semaines?select=*&order=semaine',
  parFabricant: 'v_supervision_par_fabricant?select=*',
  produitsTendus: 'v_supervision_produits_tendus?select=*',
  diffusions: 'v_diffusions?select=*&order=date_envoi.desc&limit=25',
  soumissions: 'v_diffusions_a_valider?select=*&order=cree_le.asc',
};

async function rafraichir() {
  try {
    const cles = Object.keys(LECTURES);
    const reponses = await Promise.all(cles.map((c) => interroger(LECTURES[c])));

    const frais = {};
    cles.forEach((c, i) => { frais[c] = reponses[i]; });

    etat = {
      ...frais,
      // Ces deux vues ne rendent qu'une ligne : on la déplie ici plutôt que
      // d'écrire `etat.reseau[0]` à vingt endroits.
      reseau: frais.reseau[0] ?? {},
      acteurs: frais.acteurs[0] ?? {},
    };

    tracerBadges();
    remplirCommunes();
    estimerPortee();

    tracerBandeau();
    tracerJauge(etat.reseau.taux_de_service_pct);
    tracerAnneau();
    tracerCouverture();
    tracerActivite();
    tracerChiffres();
    tracerCharge();
    tracerRupturesRecentes();
    tracerPrevision();
    tracerMetriques();
    tracerLivreursEfficaces();
    tracerProduitsApercu();

    tracerRail();
    tracerCarte();
    tracerTiroir();
    tracerTableLivreurs();
    tracerTableCommunes();

    tracerActeurs();
    tracerDemandes();
    tracerAttribution();
    tracerTableActeurs();

    tracerSoumissions();
    tracerDiffusions();

    tracerSemaines();
    tracerParFabricant();
    tracerProduitsTendus();

    tracerAnomalies();

    const heure = new Date().toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
    pouls.textContent = `lu à ${heure}`;
    pouls.dataset.etat = 'ok';
    if (pouls2) { pouls2.textContent = heure; pouls2.dataset.etat = 'ok'; }
  } catch (erreur) {
    if (erreur.message === 'session') return;
    pouls.dataset.etat = 'perdu';
    if (pouls2) pouls2.dataset.etat = 'perdu';
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
