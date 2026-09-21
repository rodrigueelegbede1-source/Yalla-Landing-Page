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

const VERT = '#229453';
const JAUNE = '#E8CF00';
const ALERTE = '#FF5C39';

const message = document.getElementById('message');
const pouls = document.getElementById('pouls');
const fProduit = document.getElementById('fenetreProduit');

let etat = { bord: {}, catalogue: [], ruptures: [] };
let filtreCommune = '';
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
      + arc(120, 120, 92, 180, 360, 20, '#EDEAE0')
      + '<text x="120" y="112" text-anchor="middle" class="jauge-valeur"'
      + ' style="fill:rgba(8,22,14,.35)">—</text></svg>';
    pied.textContent = 'Aucune de vos ruptures n’est encore close. L’indicateur '
      + 'se calcule sur celles qui ont été servies contre celles qui ne l’ont pas été.';
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
    + `L ${cx2.toFixed(2)} ${cy2.toFixed(2)} Z" fill="#0A3D24"/>`
    + '<circle cx="120" cy="120" r="7" fill="#0A3D24"/>'
    + `<text x="120" y="104" text-anchor="middle" class="jauge-valeur">${v}</text>`
    + '<text x="120" y="120" text-anchor="middle" class="jauge-unite">POUR CENT</text>'
    + '<text x="26" y="142" class="jauge-borne">0</text>'
    + '<text x="214" y="142" text-anchor="end" class="jauge-borne">100</text>'
    + '</svg>';

  pied.innerHTML = 'Calculé sur <b style="font-family:var(--ff-mono);color:var(--ink)">'
    + `${nombre(closes)}</b> rupture(s) close(s) sur votre catalogue. `
    + (v >= 80 ? 'Le réseau tient sa promesse sur votre marque.'
      : v >= 50 ? 'Tenable, mais une rupture sur deux met trop longtemps.'
        : 'Sous cinquante, vos produits manquent plus souvent qu’ils ne sont servis.');
}

/* ══ Mon réseau ═══════════════════════════════════════════ */

function tracerBord() {
  const b = etat.bord;

  const volume = document.getElementById('chiffreVolume');
  volume.textContent = montant(b.chiffre_affaires);
  volume.title = montantExact(b.chiffre_affaires);

  const echappe = Number(b.dont_distributeurs_non_rattaches ?? 0);
  const total = Number(b.chiffre_affaires ?? 0);
  document.getElementById('detailVolume').innerHTML =
    `<span>${nombre(b.ruptures_closes ?? 0)} rupture(s) close(s)</span>`
    // L'écart entre les deux mesures dit au fabricant quelle part de sa
    // distribution lui échappe. C'est l'argument commercial le plus direct du
    // produit, et il ne se voit nulle part ailleurs.
    + (echappe > 0
      ? `<span><b>${montant(echappe)}</b> par des distributeurs qui ne vous sont pas rattachés</span>`
      : '<span style="opacity:.7">tout est passé par vos distributeurs</span>');

  document.getElementById('tableEmprise').innerHTML = `<tbody>${[
    ['Références au catalogue', b.produits],
    ['Boutiques qui vous portent', b.boutiques],
    ['Distributeurs', b.distributeurs],
    ['Ruptures ouvertes', b.ruptures_ouvertes],
  ].map(([nom, v]) => `<tr>
      <td>${echapper(nom)}</td>
      <td class="num" style="font-size:16px;color:var(--green-800);font-weight:600">${nombre(v)}</td>
    </tr>`).join('')}</tbody>`;

  const cible = total > 0
    ? `${montantExact(total)} livrés sur votre catalogue.`
    : 'Aucune livraison terminée pour l’instant.';
  document.getElementById('chiffreVolume').setAttribute('aria-label', cible);
}

function tracerCommunes() {
  const boite = document.getElementById('grapheCommunes');
  const ouvertes = etat.ruptures.filter((r) => r.statut === 'signalee' && r.confirmee_le);

  if (!etat.ruptures.length) {
    boite.innerHTML = '<div class="vide" style="border:0;padding:20px 0">'
      + 'Aucune rupture signalée sur votre catalogue à ce jour.</div>';
    return;
  }

  const parCommune = new Map();
  for (const r of etat.ruptures) {
    const cle = r.commune || '—';
    if (!parCommune.has(cle)) parCommune.set(cle, { ouvertes: 0, closes: 0 });
    parCommune.get(cle)[r.statut === 'signalee' || r.statut === 'prise_en_charge'
      ? 'ouvertes' : 'closes'] += 1;
  }

  const rangs = [...parCommune.entries()]
    .map(([commune, v]) => ({ commune, ...v, total: v.ouvertes + v.closes }))
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
    const lo = (r.ouvertes / maxi) * larg;
    const lc = (r.closes / maxi) * larg;
    return `
      <text x="${margeG - 10}" y="${yy + 14}" text-anchor="end" class="graphe-etiquette">${echapper(r.commune)}</text>
      ${r.ouvertes ? `<rect x="${margeG}" y="${yy + 3}" width="${lo.toFixed(1)}" height="17" rx="2.5" fill="${ALERTE}"/>` : ''}
      ${r.closes ? `<rect x="${(margeG + lo).toFixed(1)}" y="${yy + 3}" width="${lc.toFixed(1)}" height="17" rx="2.5" fill="${VERT}"/>` : ''}
      <text x="${(margeG + lo + lc + 8).toFixed(1)}" y="${yy + 16}" class="graphe-valeur">${r.total}</text>`;
  }).join('');

  boite.innerHTML = `
    <svg viewBox="0 0 ${L} ${H}" role="img" aria-label="Ruptures par commune">${corps}</svg>
    <div class="legende" style="flex-direction:row;gap:18px;margin-top:10px">
      <div style="flex:0"><i style="background:${ALERTE}"></i>En cours</div>
      <div style="flex:0"><i style="background:${VERT}"></i>Closes</div>
    </div>`;
  void ouvertes;
}

function tracerTendus() {
  const table = document.getElementById('tableTendus');

  if (!etat.ruptures.length) {
    table.innerHTML = '<tbody><tr><td style="color:rgba(8,22,14,.5)">'
      + 'Aucune rupture à ce jour.</td></tr></tbody>';
    return;
  }

  const parProduit = new Map();
  for (const r of etat.ruptures) {
    const cle = r.produit_id;
    if (!parProduit.has(cle)) {
      parProduit.set(cle, { produit: r.produit, reference: r.reference, n: 0, boutiques: new Set() });
    }
    const e = parProduit.get(cle);
    e.n += 1;
    e.boutiques.add(r.point_de_vente);
  }

  const rangs = [...parProduit.values()].sort((a, b) => b.n - a.n).slice(0, 8);
  const maxi = Math.max(1, ...rangs.map((r) => r.n));

  table.innerHTML = `
    <thead><tr><th>Référence</th><th class="num">Signalements</th><th class="num">Boutiques</th></tr></thead>
    <tbody>${rangs.map((r) => {
      const intensite = 0.14 + (r.n / maxi) * 0.56;
      return `<tr>
        <td>${echapper(r.produit)}<small>${echapper(r.reference ?? '')}</small></td>
        <td class="num"><span class="cellule-chaude"
          style="background:rgba(255,92,57,${intensite.toFixed(2)})">${nombre(r.n)}</span></td>
        <td class="num">${nombre(r.boutiques.size)}</td>
      </tr>`;
    }).join('')}</tbody>`;
}

/* ══ Ruptures ═════════════════════════════════════════════ */

function remplirCommunes() {
  const communes = [...new Set(etat.ruptures.map((r) => r.commune).filter(Boolean))].sort();
  const select = document.getElementById('filtreCommune');
  const choix = select.value;
  select.innerHTML = '<option value="">Toutes communes</option>'
    + communes.map((c) => `<option value="${echapper(c)}">${echapper(c)}</option>`).join('');
  select.value = communes.includes(choix) ? choix : '';

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
        ? 'Aucune rupture ne correspond à ce filtre.'
        : 'Aucune rupture en cours sur votre catalogue. Vos produits sont en rayon.'}
    </div>`;
    return;
  }

  const ordonnees = [...gardees].sort(
    (a, b) => Number(b.attente_secondes ?? 0) - Number(a.attente_secondes ?? 0));

  zone.innerHTML = `<div class="table-boite"><table class="table">
    <thead><tr>
      <th>Produit</th><th>Point de vente</th><th>Commune</th>
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
          r.quantite_demandee ? ` · ${r.quantite_demandee} carton(s)` : ''}${
          r.signalement_automatique ? ' · détecté par la caisse' : ''}</small></td>
        <td>${echapper(r.point_de_vente)}</td>
        <td>${echapper(r.commune ?? '')}</td>
        <td>${r.distributeur
          ? echapper(r.distributeur)
          : '<span class="etat etat--alerte">Aucun</span>'}</td>
        <td class="num"${tendu ? ' style="color:#9B3218;font-weight:600"' : ''}>${duree(attente)}</td>
        <td>${
          r.statut === 'resolue' ? '<span class="etat etat--ok">Servie</span>'
          : r.statut === 'non_servie' ? '<span class="etat etat--alerte">Non servie</span>'
          : pris ? '<span class="etat etat--ok">Prise en charge</span>'
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
      + 'Votre catalogue est vide. Tant qu\'il l\'est, aucun commerçant ne peut '
      + 'signaler une rupture sur votre marque.</td></tr></tbody>';
    return;
  }

  const ordonnes = [...etat.catalogue].sort((a, b) => {
    if (a.disponible !== b.disponible) return a.disponible ? -1 : 1;
    return String(a.nom).localeCompare(String(b.nom));
  });

  table.innerHTML = `
    <thead><tr>
      <th>Produit</th><th>Catégorie</th><th class="num">Boutiques</th>
      <th class="num">Ruptures</th><th>État</th><th></th>
    </tr></thead>
    <tbody>${ordonnes.map((p) => `<tr>
      <td>${echapper(p.nom)}<small>${echapper(p.reference)}</small></td>
      <td>${echapper(p.categorie ?? '—')}</td>
      <td class="num">${nombre(p.boutiques_suivant ?? 0)}</td>
      <td class="num">${nombre(p.signalements_total ?? 0)}${
        Number(p.ruptures_ouvertes ?? 0) > 0
          ? ` <span style="color:#9B3218">(${p.ruptures_ouvertes} en cours)</span>` : ''}</td>
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
    ? `${produit.reference} · ${produit.signalements_total ?? 0} signalement(s) à ce jour`
    : 'Elle sera immédiatement visible des commerçants du réseau.';

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
    + 'Rien n\'est effacé : ses ruptures passées restent, et vous pouvez la '
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
    const [bord, catalogue, ruptures] = await Promise.all([
      interroger('v_tableau_de_bord_fabricant?select=*'),
      interroger('v_mon_catalogue?select=*'),
      interroger('v_mes_ruptures?select=*&order=date_signalement.desc&limit=400'),
    ]);

    etat = { bord: bord[0] ?? {}, catalogue, ruptures };

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
    tracerJauge(etat.bord.taux_de_service_pct);
    tracerBord();
    tracerCommunes();
    tracerTendus();
    tracerRuptures();
    tracerCatalogue();

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
