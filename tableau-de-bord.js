/* ═══════════════════════════════════════════════════════════
   YALLA — Tableau de bord du fabricant

   Le rôle fabricant n'avait aucune interface : il existait en
   base et dans les maquettes, et nulle part ailleurs. C'est
   pourtant lui qui paie, et le taux de service est ce qu'on lui
   vend.

   CE QUE CETTE PAGE NE MONTRE PAS, ET NE MONTRERA JAMAIS : les
   ventes et les stocks d'une boutique. Ce n'est pas un oubli mais
   la promesse faite au boutiquier, inscrite dans les politiques
   RLS de la base. Même si cette page les demandait, la base ne
   les rendrait pas.
   ═══════════════════════════════════════════════════════════ */

const URL_BASE = window.YALLA_CONFIG?.url ?? '';
const CLE = window.YALLA_CONFIG?.cle ?? '';

const jeton = sessionStorage.getItem('yalla.jeton');
const nom = sessionStorage.getItem('yalla.nom') || '';

/* La session vit dans l'onglet, pas au-delà : un tableau de bord consulté sur
   un poste partagé ne doit pas rester ouvert pour le suivant. Sans jeton, on
   renvoie à la connexion plutôt que d'afficher une page vide. */
if (!jeton) {
  location.replace('rejoindre.html');
}

const titre = document.getElementById('titreFabricant');
const sousTitre = document.getElementById('sousTitreFabricant');
const message = document.getElementById('messageBord');
const chiffres = document.getElementById('chiffres');

document.getElementById('boutonDeconnexion').addEventListener('click', () => {
  sessionStorage.clear();
  location.replace('rejoindre.html');
});

function echapper(texte) {
  const d = document.createElement('div');
  d.textContent = texte ?? '';
  return d.innerHTML;
}

function nombre(valeur) {
  if (valeur === null || valeur === undefined) return '—';
  return String(valeur).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
}

/* Un intervalle PostgreSQL arrive sous la forme « 01:47:00 » ou
   « 1 day 02:00:00 ». On le rend lisible plutôt que de l'afficher brut. */
function dureeLisible(intervalle) {
  if (!intervalle) return '—';
  const jours = /(\d+)\s+day/.exec(intervalle);
  const heures = /(\d{1,2}):(\d{2}):/.exec(intervalle);
  if (jours) return `${jours[1]} j`;
  if (!heures) return '—';
  const h = Number(heures[1]);
  const m = Number(heures[2]);
  if (h > 0) return m > 0 ? `${h} h ${m}` : `${h} h`;
  return `${m} min`;
}

async function interroger(chemin) {
  const reponse = await fetch(`${URL_BASE}/rest/v1/${chemin}`, {
    headers: { apikey: CLE, Authorization: `Bearer ${jeton}` },
  });
  if (reponse.status === 401 || reponse.status === 403) {
    sessionStorage.clear();
    location.replace('rejoindre.html');
    throw new Error('session');
  }
  if (!reponse.ok) throw new Error(`HTTP ${reponse.status}`);
  return reponse.json();
}

function afficherErreur(texte) {
  message.textContent = texte;
  message.dataset.ton = 'erreur';
  message.hidden = false;
}

/* ── Les chiffres ──────────────────────────────────────────── */

async function chargerChiffres() {
  const lignes = await interroger('v_tableau_de_bord_fabricant?select=*');
  const d = lignes[0];

  if (!d) {
    // Un compte fabricant sans ligne `fabricants`, ou dont les politiques ne
    // rendent rien. On le dit plutôt que d'afficher des tirets.
    titre.textContent = nom || 'Tableau de bord';
    sousTitre.textContent =
      'Aucune donnée ne remonte pour ce compte. Contactez l’administrateur du réseau.';
    return;
  }

  titre.textContent = d.fabricant_nom || nom;
  sousTitre.textContent = `${nombre(d.produits)} références au catalogue`;

  document.getElementById('chiffreTaux').textContent =
    d.taux_de_service_pct === null || d.taux_de_service_pct === undefined
      ? '—'
      : `${d.taux_de_service_pct} %`;

  document.getElementById('chiffreDelai').textContent =
    dureeLisible(d.delai_moyen_prise_en_charge);

  document.getElementById('chiffreOuvertes').textContent = nombre(d.ruptures_ouvertes);
  document.getElementById('chiffreReseau').textContent = nombre(d.boutiques);
  document.getElementById('detailReseau').textContent =
    `${nombre(d.distributeurs)} distributeur(s) portent votre marque.`;

  chiffres.hidden = false;

  // Le taux de service n'a de sens qu'à partir d'un volume : l'afficher sur
  // deux ruptures closes donnerait 50 % ou 100 %, et les deux mentiraient.
  if (d.ruptures_closes !== null && d.ruptures_closes < 10) {
    const note = document.createElement('em');
    note.textContent =
      ` Calculé sur ${nombre(d.ruptures_closes)} rupture(s) closes seulement :`
      + ' trop peu pour être significatif.';
    document.querySelector('.bord-chiffre--fort em').append(note);
  }
}

/* ── Les ruptures en cours ─────────────────────────────────── */

async function chargerRuptures() {
  const zone = document.getElementById('zoneRuptures');

  const lignes = await interroger(
    'v_ruptures_ouvertes?select=produit_nom,reference,point_de_vente_nom,commune,'
    + 'date_signalement,statut,escaladee_le&order=date_signalement.desc&limit=50',
  );

  if (!lignes.length) {
    zone.innerHTML =
      '<div class="bord-vide">Aucune rupture ouverte sur vos produits en ce '
      + 'moment. Vos boutiques sont servies.</div>';
    return;
  }

  const rangs = lignes.map((r) => {
    const depuis = Math.round((Date.now() - new Date(r.date_signalement)) / 60000);
    const etat = r.statut === 'prise_en_charge'
      ? '<span class="pastille pastille--ok">Prise en charge</span>'
      : r.escaladee_le
        ? '<span class="pastille pastille--attente">Ouverte à la commune</span>'
        : '<span class="pastille pastille--attente">En attente</span>';

    return `<tr>
      <td>${echapper(r.produit_nom)}<br><small style="opacity:.6">${echapper(r.reference ?? '')}</small></td>
      <td>${echapper(r.point_de_vente_nom)}</td>
      <td>${echapper(r.commune)}</td>
      <td class="num">${depuis < 60 ? `${depuis} min` : `${Math.floor(depuis / 60)} h`}</td>
      <td>${etat}</td>
    </tr>`;
  });

  zone.innerHTML = `<div class="bord-tableau-boite"><table class="bord-tableau">
    <thead><tr>
      <th>Produit</th><th>Boutique</th><th>Commune</th><th>Depuis</th><th>État</th>
    </tr></thead>
    <tbody>${rangs.join('')}</tbody>
  </table></div>`;
}

/* ── La couverture ─────────────────────────────────────────── */

async function chargerReseau() {
  const zone = document.getElementById('zoneReseau');

  const lignes = await interroger(
    'attributions_reseau?select=point_de_vente_id,points_de_vente(nom,commune,type_activite),'
    + 'distributeurs(nom)&limit=100',
  );

  if (!lignes.length) {
    zone.innerHTML =
      '<div class="bord-vide">Aucune boutique ne suit encore vos produits. '
      + 'C’est l’agent recenseur qui les inscrit, et le distributeur qui les '
      + 'rattache à votre marque.</div>';
    return;
  }

  const rangs = lignes.map((a) => {
    const pdv = a.points_de_vente ?? {};
    const dist = a.distributeurs?.nom;
    return `<tr>
      <td>${echapper(pdv.nom)}</td>
      <td>${echapper(pdv.commune)}</td>
      <td>${echapper(pdv.type_activite)}</td>
      <td>${dist
        ? echapper(dist)
        : '<span class="pastille pastille--attente">Sans distributeur</span>'}</td>
    </tr>`;
  });

  zone.innerHTML = `<div class="bord-tableau-boite"><table class="bord-tableau">
    <thead><tr>
      <th>Boutique</th><th>Commune</th><th>Type</th><th>Desservie par</th>
    </tr></thead>
    <tbody>${rangs.join('')}</tbody>
  </table></div>`;
}

/* ── Chargement ────────────────────────────────────────────── */

(async () => {
  if (!jeton) return;

  // Les trois blocs sont indépendants : celui qui échoue ne doit pas emporter
  // les autres. Un réseau qui coupe une requête sur trois est le quotidien ici.
  const resultats = await Promise.allSettled([
    chargerChiffres(),
    chargerRuptures(),
    chargerReseau(),
  ]);

  const echecs = resultats.filter(
    (r) => r.status === 'rejected' && r.reason?.message !== 'session',
  );
  if (echecs.length) {
    afficherErreur(
      'Une partie des données n’a pas pu être chargée. Rafraîchissez la page : '
      + 'sur ce réseau, un appel sur dix se coupe.',
    );
  }
})();
