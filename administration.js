/* ═══════════════════════════════════════════════════════════
   YALLA — Supervision du réseau

   L'écran de l'administrateur. Il a deux gestes, et les deux
   débloquent quelqu'un d'autre :

     1. VALIDER UNE DEMANDE. Sans lui, les inscriptions déposées
        depuis le site s'empilent dans une table que personne ne
        regarde. Le demandeur, lui, attend un appel qui ne vient
        pas.
     2. ATTRIBUER UNE BOUTIQUE. Un distributeur qui démarre ne
        voit rien : sa politique ne lui montre que les communes
        où il opère déjà, et il n'en a aucune. Sa première
        boutique doit lui être donnée de l'extérieur.

   CE QUE CET ÉCRAN NE MONTRE PAS, ET NE MONTRERA PAS : les
   ventes et le chiffre d'affaires d'une boutique. La promesse
   faite au boutiquier est que sa caisse n'appartient qu'à lui,
   et une promesse qui souffre une exception pour l'exploitant
   n'en est plus une. Les politiques de la base refusent ces
   lignes à l'administrateur ; cette page n'a donc rien à cacher,
   elle n'y a simplement pas accès.

   LE MOT DE PASSE EST FABRIQUÉ ICI, dans le navigateur, et
   affiché une seule fois. Il n'est envoyé nulle part ailleurs
   qu'à la fonction qui crée le compte, et ne part jamais par
   e-mail ni par SMS : c'est l'administrateur qui le dicte. Un
   mot de passe qui voyage dans une boîte aux lettres est un mot
   de passe partagé avec tous ceux qui y accèdent.
   ═══════════════════════════════════════════════════════════ */

const URL_BASE = window.YALLA_CONFIG?.url ?? '';
const CLE = window.YALLA_CONFIG?.cle ?? '';
const PERIODE_MS = 30000;

const jeton = sessionStorage.getItem('yalla.jeton');
const nomAdmin = sessionStorage.getItem('yalla.nom') || '';

if (!jeton) location.replace('rejoindre.html');

const sousTitre = document.getElementById('sousTitre');
const message = document.getElementById('messageBord');
const chiffres = document.getElementById('chiffres');
const pouls = document.getElementById('pouls');

const dlgValidation = document.getElementById('dialogueValidation');
const dlgAttribution = document.getElementById('dialogueAttribution');
const dlgIdentifiants = document.getElementById('dialogueIdentifiants');

/* Ce que la dernière interrogation a rendu, gardé pour remplir les fenêtres
   sans réinterroger la base au moment du clic. */
let marquesConnues = [];
let boutiquesConnues = [];
let distributeursConnus = [];
let demandeEnCours = null;
let distributeurEnCours = null;

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

function informer(texte, ton) {
  message.textContent = texte;
  message.dataset.ton = ton;
  message.hidden = false;
}

/* Mot de passe dicté de vive voix, jamais lu sur un écran par celui qui le
   tape. On retire donc tout ce qui s'entend pareil ou se lit de travers :
   ni l ni 1, ni O ni 0, ni I, ni 5 contre S. Huit caractères, comme partout
   ailleurs dans le produit. */
function motDePasseLisible() {
  const alphabet = 'ABCDEFGHJKMNPQRTUVWXY' + 'abcdefghijkmnpqrstuvwxy' + '23456789';
  const tirage = new Uint32Array(8);
  crypto.getRandomValues(tirage);
  return [...tirage].map((n) => alphabet[n % alphabet.length]).join('');
}

/* Le numéro tel qu'on le lit à voix haute, pas tel qu'il est stocké. */
function telephoneLisible(brut) {
  const v = String(brut ?? '').replace(/[^0-9]/g, '');
  const national = v.startsWith('225') ? v.slice(3) : v;
  if (national.length !== 10) return brut ?? '';
  return national.replace(/(\d{2})(?=\d)/g, '$1 ').trim();
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

/* ── Les demandes ──────────────────────────────────────────── */

const PROFILS = {
  fabricant: 'Fabricant',
  distributeur_affilie: 'Distributeur affilié',
  distributeur_independant: 'Distributeur indépendant',
};

function rendreDemandes(demandes) {
  const zone = document.getElementById('zoneDemandes');
  const attente = demandes.filter((d) => d.statut === 'en_attente');

  if (!attente.length) {
    zone.innerHTML =
      '<div class="bord-vide">Aucune demande en attente. Les inscriptions '
      + 'déposées depuis le site apparaissent ici, et personne n’obtient de '
      + 'compte sans passer par cet écran.</div>';
    return;
  }

  // Les plus anciennes en tête : une demande oubliée est un professionnel qui
  // attend un appel et finit par renoncer.
  const ordonnees = [...attente].sort(
    (a, b) => Number(b.anciennete_secondes ?? 0) - Number(a.anciennete_secondes ?? 0),
  );

  zone.innerHTML = ordonnees.map((d) => {
    const lignes = [
      d.ville ? `Ville : ${echapper(d.ville)}` : '',
      d.communes ? `Communes : ${echapper(d.communes)}` : '',
      d.marques ? `Marques : ${echapper(d.marques)}` : '',
      d.email ? `E-mail : ${echapper(d.email)}` : '',
    ].filter(Boolean);

    return `<article class="demande">
      <div class="demande-tete">
        <div>
          <strong>${echapper(d.societe)}</strong>
          <em>${echapper(d.nom)} · <a href="tel:+${echapper(d.telephone)}">${
            echapper(telephoneLisible(d.telephone))
          }</a></em>
        </div>
        <span class="pastille pastille--ok">${echapper(PROFILS[d.profil] ?? d.profil)}</span>
      </div>

      ${lignes.length ? `<ul class="demande-details"><li>${lignes.join('</li><li>')}</li></ul>` : ''}
      ${d.message ? `<p class="demande-mot">« ${echapper(d.message)} »</p>` : ''}

      <div class="demande-pied">
        <small>Déposée ${anciennete(d.anciennete_secondes)}</small>
        <div class="demande-actions">
          <button type="button" class="bord-action bord-action--discret"
                  data-refuser="${echapper(d.demande_id)}"
                  data-societe="${echapper(d.societe)}">Refuser</button>
          <button type="button" class="bord-action"
                  data-valider="${echapper(d.demande_id)}">Valider</button>
        </div>
      </div>
    </article>`;
  }).join('');

  for (const bouton of zone.querySelectorAll('[data-valider]')) {
    bouton.addEventListener('click', () => {
      ouvrirValidation(ordonnees.find((d) => d.demande_id === bouton.dataset.valider));
    });
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

  // Un distributeur affilié porte la marque d'un fabricant, et ce
  // rattachement décide de ce qu'il verra. Un indépendant n'en a pas, un
  // fabricant encore moins : le champ ne s'affiche que là où il a un sens.
  const affilie = demande.profil === 'distributeur_affilie';
  const champMarque = document.getElementById('champMarque');
  champMarque.hidden = !affilie;

  if (affilie) {
    const select = document.getElementById('marqueRattachee');
    select.innerHTML = marquesConnues.length
      ? marquesConnues.map((f) =>
          `<option value="${echapper(f.fabricant_id)}">${echapper(f.fabricant_nom)}</option>`).join('')
      : '<option value="">Aucune marque enregistrée</option>';

    // La demande dit quelles marques le distributeur déclare porter. Si l'une
    // d'elles existe déjà, on la présélectionne : c'est presque toujours la
    // bonne, et cela évite une erreur de rattachement au clic.
    const declarees = String(demande.marques ?? '').toLowerCase();
    const trouvee = marquesConnues.find((f) =>
      declarees.includes(String(f.fabricant_nom ?? '').toLowerCase()));
    if (trouvee) select.value = trouvee.fabricant_id;
  }

  document.getElementById('motDePasseGenere').value = motDePasseLisible();
  document.getElementById('messageValidation').hidden = true;
  dlgValidation.showModal();
}

document.getElementById('regenererMdp').addEventListener('click', () => {
  document.getElementById('motDePasseGenere').value = motDePasseLisible();
});

document.getElementById('annulerValidation').addEventListener('click', () => {
  dlgValidation.close();
});

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
    retour.textContent =
      'Aucune marque à rattacher. Créez d’abord le fabricant, ou validez ce '
      + 'distributeur comme indépendant.';
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

    dlgValidation.close();

    // Le mot de passe n'existe qu'ici, et cette fenêtre est la seule occasion
    // de le lire. Il n'est écrit nulle part ailleurs, volontairement.
    document.getElementById('identifiantCree').textContent =
      telephoneLisible(corps.identifiant ?? demande.telephone);
    document.getElementById('motDePasseCree').textContent = motDePasse;
    dlgIdentifiants.showModal();

    // Le compte existe, la demande n'a pas pu être marquée : l'incident est
    // rattrapable et il faut le dire, sinon l'administrateur revalidera et se
    // heurtera à « ce numéro est déjà rattaché à un compte ».
    if (corps.demande_traitee === false) {
      informer(
        'Le compte est créé, mais la demande est restée en attente à l’écran. '
        + 'Ne la validez pas une seconde fois : le compte existe déjà.',
        'erreur',
      );
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
    + 'Motif, pour la retrouver plus tard. Il n’est pas envoyé au demandeur.',
  );
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

/* ── Les anomalies ─────────────────────────────────────────── */

const ANOMALIES = {
  boutique_sans_distributeur: { titre: 'Boutique sans distributeur', gravite: 'attente' },
  distributeur_sans_livreur: { titre: 'Distributeur sans livreur', gravite: 'attente' },
  boutique_sans_stock: { titre: 'Boutique sans stock suivi', gravite: 'attente' },
  rupture_sans_destinataire: { titre: 'Rupture sans destinataire', gravite: 'attente' },
};

function rendreAnomalies(anomalies) {
  const zone = document.getElementById('zoneAnomalies');

  if (!anomalies.length) {
    zone.innerHTML =
      '<div class="bord-vide">Rien à signaler. Chaque boutique active a un '
      + 'distributeur et un stock suivi, et chaque distributeur a un livreur.</div>';
    return;
  }

  // Groupées par type : l'administrateur corrige une famille de pannes d'un
  // coup, il ne traite pas une liste mélangée ligne à ligne.
  const familles = new Map();
  for (const a of anomalies) {
    if (!familles.has(a.type_anomalie)) familles.set(a.type_anomalie, []);
    familles.get(a.type_anomalie).push(a);
  }

  zone.innerHTML = [...familles.entries()].map(([type, liste]) => {
    const meta = ANOMALIES[type] ?? { titre: type, gravite: 'attente' };
    const attribuable = type === 'boutique_sans_distributeur';

    const rangs = liste.map((a) => `<tr>
      <td>${echapper(a.objet_nom)}</td>
      <td>${echapper(a.detail ?? '')}</td>
      <td>${attribuable
        ? `<button type="button" class="bord-action bord-action--discret"
             data-attribuer="${echapper(a.objet_id)}"
             data-nom="${echapper(a.objet_nom)}">Attribuer</button>`
        : '<span style="opacity:.5">—</span>'}</td>
    </tr>`);

    return `<h3 class="bord-commune">${echapper(meta.titre)}
        <span>${liste.length}</span></h3>
      <p class="anomalie-effet">${echapper(liste[0].consequence ?? '')}</p>
      <div class="bord-tableau-boite"><table class="bord-tableau">
        <thead><tr><th>Objet</th><th>Où</th><th></th></tr></thead>
        <tbody>${rangs.join('')}</tbody>
      </table></div>`;
  }).join('');

  for (const bouton of zone.querySelectorAll('[data-attribuer]')) {
    bouton.addEventListener('click', () =>
      ouvrirAttribution(bouton.dataset.attribuer, bouton.dataset.nom));
  }
}

/* ── Les distributeurs ─────────────────────────────────────── */

function rendreDistributeurs(distributeurs) {
  const zone = document.getElementById('zoneDistributeurs');

  if (!distributeurs.length) {
    zone.innerHTML = '<div class="bord-vide">Aucun distributeur enregistré.</div>';
    return;
  }

  const rangs = distributeurs.map((d) => {
    const boutiques = Number(d.boutiques ?? 0);
    const livreurs = Number(d.livreurs ?? 0);

    // Deux états critiques, et ils ne se corrigent pas au même endroit : sans
    // boutique, c'est à l'administrateur d'agir ; sans livreur, c'est au
    // distributeur d'en enrôler un depuis l'application.
    let etat;
    if (!boutiques) {
      etat = '<span class="pastille pastille--attente">Aucune boutique</span>';
    } else if (!livreurs) {
      etat = '<span class="pastille pastille--attente">Aucun livreur</span>';
    } else {
      etat = `<span class="pastille pastille--ok">${nombre(d.livreurs_en_ligne ?? 0)} en ligne</span>`;
    }

    return `<tr>
      <td>
        ${echapper(d.nom)}
        <br><small style="opacity:.6">${
          d.fabricant_rattache
            ? `Affilié · ${echapper(d.fabricant_rattache)}`
            : 'Indépendant'
        }</small>
      </td>
      <td class="num">${echapper(telephoneLisible(d.telephone))}</td>
      <td class="num">${nombre(boutiques)}</td>
      <td class="num">${nombre(livreurs)}</td>
      <td class="num">${nombre(d.courses_en_attente ?? 0)}</td>
      <td>${etat}</td>
      <td>
        <button type="button" class="bord-action bord-action--discret"
                data-distributeur="${echapper(d.distributeur_id)}"
                data-nom="${echapper(d.nom)}">Attribuer</button>
      </td>
    </tr>`;
  });

  zone.innerHTML = `<div class="bord-tableau-boite"><table class="bord-tableau">
    <thead><tr>
      <th>Distributeur</th><th>Téléphone</th><th>Boutiques</th>
      <th>Livreurs</th><th>En attente</th><th>État</th><th></th>
    </tr></thead>
    <tbody>${rangs.join('')}</tbody>
  </table></div>`;

  for (const bouton of zone.querySelectorAll('[data-distributeur]')) {
    bouton.addEventListener('click', () =>
      ouvrirAttribution(null, null, bouton.dataset.distributeur, bouton.dataset.nom));
  }
}

/* ── Les boutiques ─────────────────────────────────────────── */

function rendreBoutiques(boutiques) {
  const zone = document.getElementById('zoneBoutiques');

  if (!boutiques.length) {
    zone.innerHTML =
      '<div class="bord-vide">Aucune boutique recensée. Le recensement se fait '
      + 'sur le terrain, depuis l’application.</div>';
    return;
  }

  const communes = new Map();
  for (const b of boutiques) {
    const cle = b.commune || '—';
    if (!communes.has(cle)) communes.set(cle, []);
    communes.get(cle).push(b);
  }

  zone.innerHTML = [...communes.entries()].map(([commune, liste]) => {
    const rangs = liste.map((b) => `<tr>
      <td>
        ${echapper(b.nom)}
        <br><small style="opacity:.6">${echapper(b.gerant_nom ?? '')}${
          b.agent_recenseur ? ` · recensée par ${echapper(b.agent_recenseur)}` : ''
        }</small>
      </td>
      <td>${b.distributeurs
        ? echapper(b.distributeurs)
        : '<span class="pastille pastille--attente">Personne</span>'}</td>
      <td>${echapper(b.marques ?? '—')}</td>
      <td class="num">${nombre(b.references_suivies ?? 0)}</td>
      <td class="num">${nombre(b.ruptures_ouvertes ?? 0)}</td>
      <td>
        <button type="button" class="bord-action bord-action--discret"
                data-boutique="${echapper(b.point_de_vente_id)}"
                data-nom="${echapper(b.nom)}">Attribuer</button>
      </td>
    </tr>`);

    return `<h3 class="bord-commune">${echapper(commune)}
        <span>${liste.length} boutique(s)</span></h3>
      <div class="bord-tableau-boite"><table class="bord-tableau">
        <thead><tr>
          <th>Boutique</th><th>Desservie par</th><th>Marques</th>
          <th>Références</th><th>Ruptures</th><th></th>
        </tr></thead>
        <tbody>${rangs.join('')}</tbody>
      </table></div>`;
  }).join('');

  for (const bouton of zone.querySelectorAll('[data-boutique]')) {
    bouton.addEventListener('click', () =>
      ouvrirAttribution(bouton.dataset.boutique, bouton.dataset.nom));
  }
}

/* ── Attribuer ─────────────────────────────────────────────── */

/* La même fenêtre s'ouvre depuis deux endroits : depuis une boutique, où le
   distributeur reste à choisir, et depuis un distributeur, où c'est la
   boutique. On verrouille ce qui est déjà connu plutôt que de le redemander. */
function ouvrirAttribution(boutiqueId, boutiqueNom, distributeurId, distributeurNom) {
  distributeurEnCours = distributeurId ?? null;

  const selBoutique = document.getElementById('boutiqueChoisie');
  const selMarque = document.getElementById('marqueChoisie');

  selMarque.innerHTML = marquesConnues.length
    ? marquesConnues.map((f) =>
        `<option value="${echapper(f.fabricant_id)}">${echapper(f.fabricant_nom)}</option>`).join('')
    : '<option value="">Aucune marque enregistrée</option>';

  if (distributeurId) {
    document.getElementById('sousTitreAttribution').textContent =
      `Vers ${distributeurNom}. Choisissez la boutique à lui confier.`;
    selBoutique.disabled = false;
    selBoutique.innerHTML = boutiquesConnues.map((b) =>
      `<option value="${echapper(b.point_de_vente_id)}">${
        echapper(b.nom)} · ${echapper(b.commune ?? '')}${
        b.distributeurs ? ` (chez ${echapper(b.distributeurs)})` : ' (libre)'
      }</option>`).join('');
  } else {
    document.getElementById('sousTitreAttribution').textContent =
      `${boutiqueNom}. Choisissez le distributeur qui la desservira.`;
    selBoutique.disabled = true;
    selBoutique.innerHTML =
      `<option value="${echapper(boutiqueId)}">${echapper(boutiqueNom)}</option>`;
  }

  // Quand le distributeur n'est pas connu d'avance, il faut le demander : on
  // réutilise le sélecteur de marque, doublé d'un sélecteur de distributeur.
  const champDist = document.getElementById('champDistributeur');
  champDist.hidden = Boolean(distributeurId);
  if (!distributeurId) {
    document.getElementById('distributeurChoisi').innerHTML =
      distributeursConnus.length
        ? distributeursConnus.map((d) =>
            `<option value="${echapper(d.distributeur_id)}">${echapper(d.nom)}${
              d.fabricant_rattache ? ` · ${echapper(d.fabricant_rattache)}` : ''
            }</option>`).join('')
        : '<option value="">Aucun distributeur enregistré</option>';
  }

  document.getElementById('messageAttribution').hidden = true;
  dlgAttribution.showModal();
}

document.getElementById('annulerAttribution').addEventListener('click', () => {
  dlgAttribution.close();
});

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

    dlgAttribution.close();

    // Reprendre une boutique à un confrère est une décision commerciale, pas
    // un détail technique. La base rend le nom du distributeur dépossédé pour
    // que l'écran puisse le dire, plutôt que d'annoncer un succès muet.
    informer(
      resultat.repris_a
        ? `${resultat.boutique} passe de ${resultat.repris_a} à `
          + `${resultat.distributeur} pour ${resultat.marque}.`
        : `${resultat.boutique} est confiée à ${resultat.distributeur} `
          + `pour ${resultat.marque}.`,
      'succes',
    );
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

/* ── Chargement ────────────────────────────────────────────── */

function rendreChiffres(reseau, anomalies) {
  const r = reseau ?? {};

  document.getElementById('chiffreTaux').textContent =
    r.taux_de_service_pct === null || r.taux_de_service_pct === undefined
      ? '—'
      : `${r.taux_de_service_pct} %`;
  document.getElementById('detailTaux').textContent =
    Number(r.ruptures_closes ?? 0) > 0
      ? `Sur ${nombre(r.ruptures_closes)} rupture(s) close(s).`
      : 'Aucune rupture close pour l’instant : l’indicateur attend le terrain.';

  document.getElementById('chiffreBoutiques').textContent = nombre(r.boutiques_actives);
  document.getElementById('detailBoutiques').textContent =
    `${nombre(r.distributeurs)} distributeur(s), ${nombre(r.fabricants)} marque(s), `
    + `${nombre(r.produits)} référence(s).`;

  document.getElementById('chiffreCourses').textContent = nombre(r.ruptures_ouvertes);
  document.getElementById('detailCourses').textContent =
    `${nombre(r.ruptures_prises)} prise(s) en charge, `
    + `${nombre(r.ruptures_a_confirmer)} en attente de confirmation du boutiquier.`;

  document.getElementById('chiffreFlotte').textContent = nombre(r.livreurs_en_ligne);
  document.getElementById('detailFlotte').textContent =
    `${nombre(r.livreurs_actifs)} livreur(s) actif(s), ${nombre(anomalies.length)} anomalie(s).`;

  chiffres.hidden = false;
}

async function rafraichir() {
  try {
    const [reseau, demandes, anomalies, distributeurs, boutiques, marques] =
      await Promise.all([
        interroger('v_supervision_reseau?select=*'),
        interroger('v_demandes_acces?select=*&order=created_at.desc'),
        interroger('v_anomalies_reseau?select=*&order=type_anomalie,depuis'),
        interroger('v_supervision_distributeurs?select=*&order=nom'),
        interroger('v_supervision_boutiques?select=*&order=commune,nom'),
        // La table plutôt que la vue de tableau de bord du fabricant : on n'a
        // besoin que des noms pour remplir deux sélecteurs, et la vue traîne
        // derrière elle des agrégats de chiffre d'affaires qui n'ont rien à
        // faire dans cet écran.
        interroger('fabricants?select=fabricant_id:id,fabricant_nom:nom&statut=eq.actif&order=nom'),
      ]);

    marquesConnues = marques;
    boutiquesConnues = boutiques;
    distributeursConnus = distributeurs;

    const attente = demandes.filter((d) => d.statut === 'en_attente').length;
    sousTitre.textContent = attente
      ? `${nomAdmin ? `${nomAdmin} · ` : ''}${attente} demande(s) à traiter`
      : `${nomAdmin ? `${nomAdmin} · ` : ''}Aucune demande en attente`;

    rendreChiffres(reseau[0], anomalies);
    rendreDemandes(demandes);
    rendreAnomalies(anomalies);
    rendreDistributeurs(distributeurs);
    rendreBoutiques(boutiques);

    const heure = new Date().toLocaleTimeString('fr-FR', {
      hour: '2-digit',
      minute: '2-digit',
    });
    pouls.textContent = `à jour ${heure}`;
    pouls.dataset.etat = 'ok';
  } catch (erreur) {
    if (erreur.message === 'session') return;
    pouls.dataset.etat = 'perdu';
    informer(
      'Les données n’ont pas pu être rafraîchies. Sur ce réseau, un appel sur '
      + 'dix se coupe : la prochaine tentative part dans trente secondes.',
      'erreur',
    );
  }
}

if (jeton) {
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
