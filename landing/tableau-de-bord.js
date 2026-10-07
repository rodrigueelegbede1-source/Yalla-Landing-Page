/* ═══════════════════════════════════════════════════════════
   YALLA — Espace fabricant

   CE QU'UN FABRICANT VIENT CHERCHER ICI, et que rien d'autre ne
   lui donne : la liste des ventes qui n'ont pas eu lieu. Une
   rupture en rayon ne laisse aucune trace dans ses relevés, ses
   commandes ou ses livraisons. Elle n'existe nulle part, sauf
   ici.

   TROIS ONGLETS, TROIS QUESTIONS :

     * Mon réseau  — comment ma marque est servie, et où
     * Ruptures    — ce qui manque en ce moment, chez qui
     * Catalogue   — ce que le réseau connaît de moi

   LE CLOISONNEMENT NE VIT PAS DANS CETTE PAGE. Les vues
   `v_mon_catalogue` et `v_mes_ruptures` filtrent sur l'identité
   lue dans le jeton, et les politiques de la base doublent ce
   filtre. Un fabricant qui interrogerait l'API directement, sans
   passer par cet écran, obtiendrait exactement la même chose.
   C'est la seule forme de cloisonnement qui tienne : celle qu'on
   ne peut pas contourner avec la console du navigateur.

   AUCUNE BIBLIOTHÈQUE EXTÉRIEURE. Jauge et histogrammes sont
   tracés en SVG. En charger une obligerait à élargir
   `script-src` dans la politique de sécurité du site, qui
   s'applique à toutes ses pages.
   ═══════════════════════════════════════════════════════════ */

const URL_BASE = window.YALLA_CONFIG?.url ?? '';
const CLE = window.YALLA_CONFIG?.cle ?? '';
const PERIODE_MS = 30000;

const jeton = sessionStorage.getItem('yalla.jeton');
const nomFabricant = sessionStorage.getItem('yalla.nom') || 'Fabricant';

if (!jeton) location.replace('rejoindre.html');

const VERT = '#146B3A';
const JAUNE = '#FFE500';
const ALERTE = '#D65C52';

const message = document.getElementById('message');
const pouls = document.getElementById('pouls');
const fProduit = document.getElementById('fenetreProduit');

let etat = { bord: {}, catalogue: [], ruptures: [], activite: [] };
let filtreCommune = '';
let filtreCommuneTableau = '';
let filtreEtat = 'ouvertes';
let produitEnCours = null;

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

/* ══ Navigation ═══════════════════════════════════════════ */

const VOLETS = {
  tableau: 'voletTableau',
  ruptures: 'voletRuptures',
  catalogue: 'voletCatalogue',
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

/* ══ La jauge ═════════════════════════════════════════════ */

function pointCercle(cx, cy, r, degres) {
  const a = (degres * Math.PI) / 180;
  return [cx + r * Math.cos(a), cy + r * Math.sin(a)];
}

function arc(cx, cy, r, de, a, epaisseur, couleur) {
  const [x1, y1] = pointCercle(cx, cy, r, de);
  const [x2, y2] = pointCercle(cx, cy, r, a);
  return `<path d="M ${x1.toFixed(2)} ${y1.toFixed(2)} A ${r} ${r} 0 0 1 `
    + `${x2.toFixed(2)} ${y2.toFixed(2)}" fill="none" stroke="${couleur}" `
    + `stroke-width="${epaisseur}"/>`;
}

/* Trois bandes plutôt qu'un dégradé : le lecteur doit pouvoir dire « on est
   dans le rouge » sans lire le chiffre. Les seuils, 50 et 80, sont ceux qu'on
   défend devant le fabricant, donc ceux qu'il doit voir. */
function tracerJauge(valeur) {
  const boite = document.getElementById('jaugeService');
  const pied = document.getElementById('piedService');
  const closes = Number(etat.bord.ruptures_closes ?? 0);

  if (valeur === null || valeur === undefined) {
    boite.innerHTML = '<svg viewBox="0 0 240 150" role="img" aria-label="Taux de service indisponible">'
      + arc(120, 120, 92, 180, 360, 20, '#E6EBE5')
      + '<text x="120" y="112" text-anchor="middle" class="jauge-valeur"'
      + ' style="fill:rgba(8,22,14,.35)">—</text></svg>';
    pied.textContent = 'Aucune de vos demandes n’est encore clôturée. L’indicateur '
      + 'se calcule sur celles qui ont été livrées et celles qui ne l’ont pas été.';
    return;
  }

  const v = Math.max(0, Math.min(100, Number(valeur)));
  const angle = 180 + (v / 100) * 180;
  const [ax, ay] = pointCercle(120, 120, 72, angle);
  const [bx, by] = pointCercle(120, 120, 10, angle + 90);
  const [cx2, cy2] = pointCercle(120, 120, 10, angle - 90);

  boite.innerHTML = `<svg viewBox="0 0 240 150" role="img" aria-label="Taux de service ${v} %">`
    + arc(120, 120, 92, 180, 270, 20, ALERTE)
    + arc(120, 120, 92, 270, 324, 20, JAUNE)
    + arc(120, 120, 92, 324, 360, 20, VERT)
    + `<path d="M ${ax.toFixed(2)} ${ay.toFixed(2)} L ${bx.toFixed(2)} ${by.toFixed(2)} `
    + `L ${cx2.toFixed(2)} ${cy2.toFixed(2)} Z" fill="#102A23"/>`
    + '<circle cx="120" cy="120" r="7" fill="#102A23"/>'
    + `<text x="120" y="104" text-anchor="middle" class="jauge-valeur">${v}</text>`
    + '<text x="120" y="120" text-anchor="middle" class="jauge-unite">POUR CENT</text>'
    + '<text x="26" y="142" class="jauge-borne">0</text>'
    + '<text x="214" y="142" text-anchor="end" class="jauge-borne">100</text>'
    + '</svg>';

  pied.innerHTML = 'Calculé sur <b style="font-family:var(--ff-mono);color:var(--ink)">'
    + `${nombre(closes)}</b> demande(s) clôturée(s) sur votre catalogue. `
    + (v >= 80 ? 'Le réseau tient sa promesse sur votre marque.'
      : v >= 50 ? 'Tenable, mais une rupture sur deux met trop longtemps.'
        : 'Sous cinquante, vos produits manquent plus souvent qu’ils ne sont servis.');
}

/* ══ Mon réseau ═══════════════════════════════════════════ */

function tracerJaugeService(valeur) {
  const kpi = document.getElementById('chiffreService');
  const detailKpi = document.getElementById('detailService');
  const closes = Number(etat.bord.ruptures_closes ?? 0);

  if (valeur === null || valeur === undefined) {
    kpi.textContent = '—';
    detailKpi.textContent = 'Aucune demande clôturée';
    return;
  }
  const v = Math.max(0, Math.min(100, Number(valeur)));
  kpi.textContent = `${v} %`;
  detailKpi.textContent = `Sur ${nombre(closes)} demande(s) clôturée(s)`;
}

function tracerBord() {
  const b = etat.bord;

  const nomDeNomination = b.fabricant_nom || nomFabricant;
  const optionEspace = document.getElementById('optionEspaceFabricant');
  if (optionEspace) optionEspace.textContent = `Fabricant · ${nomDeNomination}`;

  document.getElementById('chiffrePoints').textContent = nombre(b.boutiques);
  document.getElementById('detailPoints').innerHTML =
    `<span>${nombre(b.distributeurs)} distributeur(s)</span>`;

  document.getElementById('chiffreRuptures').textContent = nombre(b.ruptures_ouvertes);
  const sansDistributeur = etat.ruptures.filter(
    (r) => (r.statut === 'signalee' || r.statut === 'prise_en_charge') && !r.distributeur).length;
  document.getElementById('detailRuptures').innerHTML =
    `<span><b>${nombre(sansDistributeur)}</b> sans distributeur</span>`;

  document.getElementById('chiffreProduits').textContent = nombre(b.produits);
  const actives = etat.catalogue.filter((p) => p.disponible).length;
  document.getElementById('detailProduits').innerHTML =
    `<span>${nombre(actives)} en service</span>`;

  document.getElementById('tableChiffres').innerHTML = [
    ['Revendeurs qui vous référencent', b.boutiques, ''],
    ['Distributeurs', b.distributeurs, ''],
    ['Références au catalogue', b.produits, `${nombre(actives)} en service`],
    ['Demandes en cours', b.ruptures_ouvertes, ''],
  ].map(([nom2, v, detail]) => `
    <div class="network-stat">
      <strong>${nombre(v)}</strong>
      <span>${echapper(nom2)}${detail ? ` · ${echapper(detail)}` : ''}</span>
    </div>`).join('');
}

/* ── Le rythme, sur ce que le fabricant peut légitimement voir : les demandes
   visibles dans son périmètre de catalogue et ses propres livraisons
   confirmées (voir le bandeau de confidentialité). ─────────────────────── */
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
      `<circle cx="${(margeG + i * pas + pas / 2).toFixed(1)}" cy="${y(Number(j.resolues)).toFixed(1)}" r="3.2" fill="${VERT}"/>`).join('');

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
      <div style="flex:0"><i style="background:${VERT}"></i>Livraisons</div>
    </div>`;

  const aujourdhui = jours[jours.length - 1];
  const total14 = jours.reduce((s, j) => s + Number(j.signalees), 0);
  pied.textContent = total14 === 0
    ? 'Rien n’a bougé sur ces quatorze jours sur votre catalogue.'
    : `${nombre(aujourdhui.resolues)} livraison(s) confirmée(s) aujourd’hui, sur ${nombre(total14)} demande(s) visibles ces quatorze derniers jours.`;
}

/* ── Couverture : la part de vos références actuellement en rupture, et la
   répartition des demandes en cours par commune (pas de roster complet des
   revendeurs côté fabricant, donc pas de taux de service par commune). ──── */
function tracerCouverture() {
  const anneau = document.getElementById('anneauCouverture');
  const valeur = document.getElementById('valeurCouverture');
  const copie = document.getElementById('texteCouverture');
  const barres = document.getElementById('communesCouverture');
  const pied = document.getElementById('piedCouverture');

  const produits = Number(etat.bord.produits ?? 0);
  const ouvertes = Number(etat.bord.ruptures_ouvertes ?? 0);
  const part = produits === 0 ? 0 : Math.min(100, Math.round((ouvertes / produits) * 100));

  anneau.style.background = `conic-gradient(${ALERTE} 0 ${part}%, #e6ebe5 ${part}% 100%)`;
  valeur.textContent = `${part} %`;
  copie.innerHTML = `<strong>${nombre(ouvertes)} référence(s) en rupture</strong>`
    + `<p>Sur ${nombre(produits)} référence(s) à votre catalogue.</p>`;

  const enCours = etat.ruptures.filter(
    (r) => (r.statut === 'signalee' || r.statut === 'prise_en_charge')
      && (!filtreCommuneTableau || r.commune === filtreCommuneTableau));
  const parCommune = new Map();
  for (const r of enCours) {
    const cle = r.commune || '—';
    parCommune.set(cle, (parCommune.get(cle) ?? 0) + 1);
  }
  const totalEnCours = enCours.length;
  const rangs = [...parCommune.entries()]
    .map(([commune, n]) => ({ commune, n, taux: totalEnCours === 0 ? 0 : Math.round((n / totalEnCours) * 100) }))
    .sort((a, b) => b.n - a.n)
    .slice(0, 6);

  barres.innerHTML = !rangs.length
    ? '<div class="vide" style="border:0;padding:8px 0">Aucune demande en cours sur votre catalogue.</div>'
    : rangs.map((r) => `<div class="commune-row">
        <span>${echapper(r.commune)}</span>
        <div class="track"><i style="width:${r.taux}%"></i></div>
        <b>${nombre(r.n)}</b>
      </div>`).join('');

  pied.textContent = produits === 0
    ? 'Votre catalogue est vide.'
    : ouvertes === 0
      ? 'Aucune de vos références n’est en rupture pour l’instant.'
      : `${nombre(ouvertes)} référence(s) sur ${nombre(produits)} manquent quelque part sur le réseau.`;
}

/* ── Les demandes en cours, les plus en attente d'abord ──────────────── */
function tracerDemandesEnCours() {
  const boite = document.getElementById('demandesEnCoursListe');
  const pied = document.getElementById('piedRuptures');

  const enCours = etat.ruptures.filter((r) => r.statut !== 'resolue' && r.statut !== 'non_servie' && r.statut !== 'prise_en_charge');
  const total = enCours.length;

  if (!total) {
    boite.innerHTML = '<div class="vide" style="border:0;padding:12px 0">'
      + 'Aucune demande en cours sur votre catalogue.</div>';
  } else {
    const ordonnees = [...enCours]
      .sort((a, b) => Number(b.attente_secondes ?? 0) - Number(a.attente_secondes ?? 0))
      .slice(0, 6);

    boite.innerHTML = ordonnees.map((r) => {
      const attente = Number(r.attente_secondes ?? 0);
      const progression = Math.min(100, Math.round((attente / 7200) * 100));
      return `<div class="signal-item">
        <div class="signal-heading">
          <strong>${echapper(r.produit)} · ${echapper(r.point_de_vente)}</strong>
          <span class="status">${r.confirmee_le ? 'En attente' : 'À confirmer'}</span>
        </div>
        <div class="signal-meta"><span>${echapper(r.commune ?? '')}${
          r.distributeur ? ` · ${echapper(r.distributeur)}` : ' · Sans distributeur'}</span><span>${duree(attente)}</span></div>
        <div class="signal-meter"><i style="width:${progression}%"></i></div>
      </div>`;
    }).join('');
  }

  const sansDistributeur = enCours.filter((r) => r.statut === 'signalee' && !r.distributeur).length;
  pied.textContent = total === 0
    ? 'Aucune demande en cours sur votre catalogue.'
    : sansDistributeur > 0
      ? `${sansDistributeur} attend${sansDistributeur > 1 ? 'ent' : ''} la confirmation du revendeur.`
      : 'Toutes les demandes en cours sont confirmées et visibles des distributeurs.';
}

/* ── Prévision et valeur des livraisons, sur vos seules livraisons ───── */
function tracerPrevision() {
  const boite = document.getElementById('previsionListe');
  const jours = etat.activite;
  const aujourdhui = jours.length ? jours[jours.length - 1] : null;
  const duJour = Number(aujourdhui?.montant ?? 0);
  const livraisons = Number(aujourdhui?.resolues ?? 0);
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

/* ── Les métriques honnêtes : ce qui se calcule vraiment ─────────────── */
function tracerMetriques() {
  const seuil = Date.now() - 30 * 24 * 3600 * 1000;
  const recents = etat.catalogue.filter((p) => p.created_at && new Date(p.created_at).getTime() >= seuil);
  document.getElementById('metricNouveaux').textContent = nombre(recents.length);

  const delai = etat.bord.delai_moyen_prise_en_charge;
  document.getElementById('metricDelai').textContent =
    delai === null || delai === undefined ? 'Non suivi' : duree(Number(delai));
}

/* ── Demandes récentes, les plus récentes d'abord ────────────────────── */
function tracerDemandesRecentes() {
  const boite = document.getElementById('demandesRecentesListe');

  if (!etat.ruptures.length) {
    boite.innerHTML = '<div class="vide" style="border:0;padding:12px 0">'
      + 'Aucune demande reçue sur votre catalogue à ce jour.</div>';
    return;
  }

  const ordonnees = [...etat.ruptures]
    .sort((a, b) => Number(a.attente_secondes ?? 0) - Number(b.attente_secondes ?? 0))
    .slice(0, 8);

  boite.innerHTML = ordonnees.map((r) => {
    const attente = Number(r.attente_secondes ?? 0);
    const pris = r.statut === 'prise_en_charge';
    const point = r.statut === 'resolue' ? 'done' : pris ? 'route' : '';
    const libelle = r.statut === 'resolue' ? 'Livrée' : r.statut === 'non_servie' ? 'Non livrée'
      : pris ? 'Prise en charge' : r.confirmee_le ? 'En attente' : 'À confirmer';
    return `<div class="event-item">
      <span class="event-dot ${point}"></span>
      <div class="event-main">
        <strong>${echapper(r.produit)} · ${echapper(r.point_de_vente)}</strong>
        <span>${echapper(r.commune ?? '')}${r.distributeur ? ` · ${echapper(r.distributeur)}` : ''}</span>
      </div>
      <div class="event-value">${duree(attente)}<small>${libelle}</small></div>
    </div>`;
  }).join('');
}

/* ── Les distributeurs les plus actifs sur votre catalogue ───────────── */
function tracerDistributeursActifs() {
  const boite = document.getElementById('distributeursActifsListe');
  const parDistributeur = new Map();
  for (const r of etat.ruptures) {
    if (!r.distributeur || r.statut !== 'resolue') continue;
    parDistributeur.set(r.distributeur, (parDistributeur.get(r.distributeur) ?? 0) + 1);
  }
  const classes = [...parDistributeur.entries()]
    .map(([nom2, n]) => ({ nom: nom2, n }))
    .sort((a, b) => b.n - a.n)
    .slice(0, 6);

  if (!classes.length) {
    boite.innerHTML = '<div class="vide" style="border:0;padding:12px 0;color:#a9b9ae">'
      + 'Non suivi : aucune demande de votre catalogue n’est encore livrée.</div>';
    return;
  }

  const maxi = Math.max(1, ...classes.map((d) => d.n));
  boite.innerHTML = classes.map((d) => `<div class="rank-item">
    <div class="rank-heading"><strong>${echapper(d.nom)}</strong><span>${nombre(d.n)}</span></div>
    <div class="rank-meter"><i style="width:${Math.round((d.n / maxi) * 100)}%"></i></div>
    <div class="rank-sub">Demandes de votre catalogue livrées, historique complet</div>
  </div>`).join('');
}

/* ── Charges des distributeurs, sur les demandes en cours de votre catalogue ── */
function tracerChargesApercu() {
  const boite = document.getElementById('chargesApercuListe');
  const parDistributeur = new Map();
  for (const r of etat.ruptures) {
    if (!r.distributeur || (r.statut !== 'signalee' && r.statut !== 'prise_en_charge')) continue;
    parDistributeur.set(r.distributeur, (parDistributeur.get(r.distributeur) ?? 0) + 1);
  }
  const classes = [...parDistributeur.entries()]
    .map(([nom2, n]) => ({ nom: nom2, n }))
    .sort((a, b) => b.n - a.n)
    .slice(0, 6);

  if (!classes.length) {
    boite.innerHTML = '<div class="vide" style="border:0;padding:12px 0">Aucune demande en cours chez vos distributeurs.</div>';
    return;
  }

  const maxi = Math.max(1, ...classes.map((d) => d.n));
  boite.innerHTML = classes.map((d) => `<div class="rank-item">
    <div class="rank-heading"><strong>${echapper(d.nom)}</strong><span>${nombre(d.n)}</span></div>
    <div class="rank-meter"><i style="width:${Math.round((d.n / maxi) * 100)}%"></i></div>
  </div>`).join('');
}

/* ── Vos références les plus demandées ───────────────────────────────── */
function tracerProduitsApercu() {
  const boite = document.getElementById('produitsApercuListe');

  const ordonnes = [...etat.catalogue]
    .filter((p) => Number(p.signalements_total ?? 0) > 0)
    .sort((a, b) => Number(b.signalements_total) - Number(a.signalements_total))
    .slice(0, 6);

  if (!ordonnes.length) {
    boite.innerHTML = '<div class="vide" style="border:0;padding:12px 0;color:#a9b9ae">'
      + 'Aucune demande enregistrée à ce jour.</div>';
    return;
  }

  const maxi = Math.max(1, ...ordonnes.map((p) => Number(p.signalements_total)));

  boite.innerHTML = ordonnes.map((p, i) => {
    const n = Number(p.signalements_total);
    return `<div class="product-row">
      <span class="product-rank">${i + 1}</span>
      <span class="product-name">${echapper(p.nom)}<br><small style="opacity:.75">${echapper(p.categorie ?? '')}</small></span>
      <div class="product-bar"><i style="width:${Math.round((n / maxi) * 100)}%"></i></div>
      <span class="product-count">${nombre(n)} demande(s)</span>
    </div>`;
  }).join('');
}

/* ══ Ruptures ═════════════════════════════════════════════ */

function remplirCommunes() {
  const communes = [...new Set(etat.ruptures.map((r) => r.commune).filter(Boolean))].sort();
  const options = communes.map((c) => `<option value="${echapper(c)}">${echapper(c)}</option>`).join('');

  const select = document.getElementById('filtreCommune');
  const choix = select.value;
  select.innerHTML = `<option value="">Toutes communes</option>${options}`;
  select.value = communes.includes(choix) ? choix : '';

  const tableau = document.getElementById('filtreCommuneTableau');
  const choixTableau = tableau.value;
  tableau.innerHTML = `<option value="">Toutes les communes</option>${options}`;
  tableau.value = communes.includes(choixTableau) ? choixTableau : '';

  const categories = [...new Set(etat.catalogue.map((p) => p.categorie).filter(Boolean))].sort();
  document.getElementById('listeCategories').innerHTML =
    categories.map((c) => `<option value="${echapper(c)}">`).join('');
}

for (const id of ['filtreCommune', 'filtreEtat']) {
  document.getElementById(id).addEventListener('change', () => {
    filtreCommune = document.getElementById('filtreCommune').value;
    filtreEtat = document.getElementById('filtreEtat').value;
    tracerRuptures();
  });
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

function tracerRuptures() {
  const zone = document.getElementById('zoneRuptures');

  const gardees = etat.ruptures.filter((r) => {
    if (filtreCommune && r.commune !== filtreCommune) return false;
    if (filtreEtat === 'ouvertes') return r.statut === 'signalee' || r.statut === 'prise_en_charge';
    if (filtreEtat === 'toutes') return true;
    return r.statut === filtreEtat;
  });

  if (!gardees.length) {
    zone.innerHTML = `<div class="vide">
      <b>Rien à afficher</b>
      ${filtreCommune || filtreEtat !== 'ouvertes'
        ? 'Aucune demande ne correspond à ce filtre.'
        : 'Aucune demande en cours sur votre catalogue.'}
    </div>`;
    return;
  }

  const ordonnees = [...gardees].sort(
    (a, b) => Number(b.attente_secondes ?? 0) - Number(a.attente_secondes ?? 0));

  zone.innerHTML = `<div class="table-boite"><table class="table">
    <thead><tr>
      <th>Produit</th><th>Revendeur</th><th>Commune</th>
      <th>Distributeur</th><th class="num">Attente</th><th>État</th>
    </tr></thead>
    <tbody>${ordonnees.map((r) => {
      const attente = Number(r.attente_secondes ?? 0);
      const pris = r.statut === 'prise_en_charge';
      const close = r.statut === 'resolue' || r.statut === 'non_servie';
      // Deux heures : le seuil d'escalade. Au-delà, la course est ouverte aux
      // distributeurs voisins, et le retard devient visible de tout le monde.
      const tendu = !pris && !close && attente > 7200;
      return `<tr>
        <td>${echapper(r.produit)}<small>${echapper(r.reference ?? '')}${
          r.quantite_demandee ? ` · ${r.quantite_demandee} carton(s)` : ''}</small></td>
        <td>${echapper(r.point_de_vente)}</td>
        <td>${echapper(r.commune ?? '')}</td>
        <td>${r.distributeur
          ? echapper(r.distributeur)
          : '<span class="etat etat--alerte">Aucun</span>'}</td>
        <td class="num"${tendu ? ' style="color:#D65C52;font-weight:600"' : ''}>${duree(attente)}</td>
        <td>${
          r.statut === 'resolue' ? '<span class="etat etat--ok">Livrée</span>'
          : r.statut === 'non_servie' ? '<span class="etat etat--alerte">Non livrée</span>'
          : pris ? '<span class="etat etat--ok">En livraison</span>'
          : r.confirmee_le ? '<span class="etat etat--alerte">En attente</span>'
          : '<span class="etat etat--dort">À confirmer</span>'}</td>
      </tr>`;
    }).join('')}</tbody>
  </table></div>`;
}

/* ══ Catalogue ════════════════════════════════════════════ */

function tracerCatalogue() {
  const table = document.getElementById('tableCatalogue');
  const resume = document.getElementById('resumeCatalogue');

  const actifs = etat.catalogue.filter((p) => p.disponible).length;
  const retires = etat.catalogue.length - actifs;
  resume.textContent = etat.catalogue.length === 0
    ? ''
    : `${actifs} référence(s) en service${retires ? `, ${retires} retirée(s)` : ''}.`;

  if (!etat.catalogue.length) {
    table.innerHTML = '<tbody><tr><td style="color:rgba(8,22,14,.5)">'
      + 'Votre catalogue est vide. Tant qu\'il l\'est, aucun revendeur ne peut '
      + 'vous envoyer de demande pour vos références.</td></tr></tbody>';
    return;
  }

  const ordonnes = [...etat.catalogue].sort((a, b) => {
    if (a.disponible !== b.disponible) return a.disponible ? -1 : 1;
    return String(a.nom).localeCompare(String(b.nom));
  });

  table.innerHTML = `
    <thead><tr>
      <th>Produit</th><th>Catégorie</th><th class="num">Revendeurs</th>
      <th class="num">Demandes</th><th>État</th><th></th>
    </tr></thead>
    <tbody>${ordonnes.map((p) => `<tr>
      <td>${echapper(p.nom)}<small>${echapper(p.reference)}</small></td>
      <td>${echapper(p.categorie ?? '—')}</td>
      <td class="num">${nombre(p.boutiques_suivant ?? 0)}</td>
      <td class="num">${nombre(p.signalements_total ?? 0)}${
        Number(p.ruptures_ouvertes ?? 0) > 0
          ? ` <span style="color:#D65C52">(${p.ruptures_ouvertes} en cours)</span>` : ''}</td>
      <td>${p.disponible
        ? '<span class="etat etat--ok">En service</span>'
        : '<span class="etat etat--dort">Retirée</span>'}</td>
      <td style="text-align:end;white-space:nowrap">
        <button type="button" class="bouton bouton--creux"
                data-modifier="${echapper(p.produit_id)}">Modifier</button>
        <button type="button" class="bouton ${p.disponible ? 'bouton--danger' : 'bouton--creux'}"
                data-basculer="${echapper(p.produit_id)}"
                data-actif="${p.disponible}">${p.disponible ? 'Retirer' : 'Remettre'}</button>
      </td>
    </tr>`).join('')}</tbody>`;

  for (const bouton of table.querySelectorAll('[data-modifier]')) {
    bouton.addEventListener('click', () =>
      ouvrirProduit(etat.catalogue.find((p) => p.produit_id === bouton.dataset.modifier)));
  }
  for (const bouton of table.querySelectorAll('[data-basculer]')) {
    bouton.addEventListener('click', () => basculerProduit(bouton.dataset));
  }
}

function ouvrirProduit(produit) {
  produitEnCours = produit ?? null;

  document.getElementById('titreProduit').textContent =
    produit ? 'Modifier la référence' : 'Ajouter une référence';
  document.getElementById('sousTitreProduit').textContent = produit
    ? `${produit.reference} · ${produit.signalements_total ?? 0} demande(s) à ce jour`
    : 'Elle sera immédiatement visible des revendeurs du réseau.';

  document.getElementById('produitNom').value = produit?.nom ?? '';
  document.getElementById('produitCategorie').value = produit?.categorie ?? '';
  document.getElementById('produitReference').value = '';

  // La référence est imprimée sur des bons de livraison déjà partis. La
  // modifier après coup rendrait illisibles des documents papier que personne
  // ne peut corriger : le champ disparaît en modification.
  document.getElementById('champReference').hidden = Boolean(produit);

  document.getElementById('messageProduit').hidden = true;
  fProduit.showModal();
}

document.getElementById('boutonAjouter').addEventListener('click', () => ouvrirProduit(null));
document.getElementById('annulerProduit').addEventListener('click', () => fProduit.close());

document.getElementById('confirmerProduit').addEventListener('click', async () => {
  const bouton = document.getElementById('confirmerProduit');
  const retour = document.getElementById('messageProduit');

  const nom = document.getElementById('produitNom').value.trim();
  const categorie = document.getElementById('produitCategorie').value.trim();
  const reference = document.getElementById('produitReference').value.trim();

  if (nom.length < 2) {
    retour.textContent = 'Donnez un nom à ce produit.';
    retour.dataset.ton = 'erreur';
    retour.hidden = false;
    return;
  }

  bouton.disabled = true;
  bouton.textContent = 'Enregistrement…';

  try {
    const r = await interroger('rpc/enregistrer_produit', {
      method: 'POST',
      body: JSON.stringify({
        p_nom: nom,
        p_categorie: categorie || null,
        p_reference: produitEnCours ? null : (reference || null),
        p_produit_id: produitEnCours?.produit_id ?? null,
        p_disponible: produitEnCours ? produitEnCours.disponible : true,
      }),
    });

    fProduit.close();
    informer(r.cree
      ? `« ${nom} » est au catalogue, référence ${r.reference}.`
      : `« ${nom} » est à jour.`, 'succes');
    await rafraichir();
  } catch (erreur) {
    if (erreur.message === 'session') return;
    retour.textContent = erreur.message;
    retour.dataset.ton = 'erreur';
    retour.hidden = false;
  } finally {
    bouton.disabled = false;
    bouton.textContent = 'Enregistrer';
  }
});

async function basculerProduit({ basculer: id, actif }) {
  const produit = etat.catalogue.find((p) => p.produit_id === id);
  if (!produit) return;
  const retirer = actif === 'true';

  if (retirer && !confirm(
    `Retirer « ${produit.nom} » du catalogue ?\n\n`
    + 'Rien n\'est effacé : son historique de demandes reste, et vous pouvez la '
    + 'remettre en service à tout moment. Elle cesse simplement d\'apparaître '
    + 'chez les commerçants.',
  )) return;

  try {
    await interroger('rpc/enregistrer_produit', {
      method: 'POST',
      body: JSON.stringify({
        p_nom: produit.nom,
        p_categorie: produit.categorie,
        p_produit_id: produit.produit_id,
        p_disponible: !retirer,
      }),
    });
    informer(`« ${produit.nom} » ${retirer ? 'est retirée' : 'est de nouveau en service'}.`,
      'succes');
    await rafraichir();
  } catch (erreur) {
    if (erreur.message === 'session') return;
    informer(erreur.message, 'erreur');
  }
}

/* ══ Chargement ═══════════════════════════════════════════ */

async function rafraichir() {
  try {
    const [bord, catalogue, ruptures, activite] = await Promise.all([
      interroger('v_tableau_de_bord_fabricant?select=*'),
      interroger('v_mon_catalogue?select=*'),
      interroger('v_mes_ruptures?select=*&order=date_signalement.desc&limit=400'),
      interroger('v_supervision_activite?select=*&order=jour'),
    ]);

    etat = { bord: bord[0] ?? {}, catalogue, ruptures, activite };

    const nom = etat.bord.fabricant_nom || nomFabricant;
    document.getElementById('nomFabricant').textContent = nom;
    document.getElementById('initiales').textContent = nom
      .split(/\s+/).filter(Boolean).slice(0, 2).map((m) => m[0].toUpperCase()).join('') || 'F';

    const ouvertes = ruptures.filter(
      (r) => r.statut === 'signalee' && r.confirmee_le).length;
    const compteur = document.getElementById('compteurRuptures');
    compteur.textContent = ouvertes;
    compteur.hidden = ouvertes === 0;
    compteur.dataset.urgent = ouvertes > 0 ? 'oui' : 'non';

    remplirCommunes();
    tracerJaugeService(etat.bord.taux_de_service_pct);
    tracerBord();
    tracerActivite();
    tracerCouverture();
    tracerDemandesEnCours();
    tracerPrevision();
    tracerMetriques();
    tracerDemandesRecentes();
    tracerDistributeursActifs();
    tracerChargesApercu();
    tracerProduitsApercu();
    tracerRuptures();
    tracerCatalogue();

    const heure = new Date().toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
    pouls.textContent = `lu à ${heure}`;
    pouls.dataset.etat = 'ok';
    const pouls2 = document.getElementById('pouls2');
    if (pouls2) { pouls2.textContent = heure; pouls2.dataset.etat = 'ok'; }
  } catch (erreur) {
    if (erreur.message === 'session') return;
    pouls.dataset.etat = 'perdu';
    const pouls2 = document.getElementById('pouls2');
    if (pouls2) pouls2.dataset.etat = 'perdu';
    informer('Les données n’ont pas pu être rafraîchies. Sur ce réseau, un appel '
      + 'sur dix se coupe : la prochaine tentative part dans trente secondes.', 'erreur');
  }
}

if (jeton) {
  if (VOLETS[location.hash.slice(1)]) ouvrirVolet(location.hash.slice(1));

  rafraichir();

  let minuteur = setInterval(rafraichir, PERIODE_MS);
  document.addEventListener('visibilitychange', () => {
    clearInterval(minuteur);
    if (!document.hidden) {
      rafraichir();
      minuteur = setInterval(rafraichir, PERIODE_MS);
    }
  });
}
