/* ═══════════════════════════════════════════════════════════
   YALLA — Espace professionnel

   Connexion et demande d'accès, en `fetch` direct sur l'API
   Supabase plutôt qu'avec son SDK.

   POURQUOI PAS LE SDK : la page n'a besoin que de deux appels, et
   charger un client depuis un CDN obligerait à élargir
   `script-src` dans la politique de sécurité du site. Deux
   `fetch` coûtent moins cher qu'une exception dans la CSP.

   LA CLÉ PUBLIABLE EST PUBLIQUE PAR CONCEPTION. Elle est lisible
   ici comme dans n'importe quel APK décompilé, et ce n'est pas
   elle qui protège quoi que ce soit : ce sont les politiques RLS
   de la base. La clé de service, elle, n'entre jamais dans une
   page.
   ═══════════════════════════════════════════════════════════ */

/* Les deux valeurs viennent de config.js, écrit au déploiement par
   scripts/publier-acces.sh depuis le .env. Rien n'est saisi à la main ici :
   une clé recopiée de mémoire est une clé fausse, et l'erreur ne se voit qu'au
   premier visiteur qui essaie de se connecter. C'est arrivé en écrivant ce
   fichier. */
const SUPABASE_URL = window.YALLA_CONFIG?.url ?? '';
const SUPABASE_CLE = window.YALLA_CONFIG?.cle ?? '';

if (!SUPABASE_URL || !SUPABASE_CLE) {
  console.error('config.js manquant : lancez scripts/publier-acces.sh');
}

/* ── Téléphone ─────────────────────────────────────────────
   Même normalisation qu'en SQL, en Dart, dans la fonction Edge et
   dans les scripts. Les cinq doivent rendre EXACTEMENT le même
   résultat, sans quoi un compte se crée sous une adresse et se
   connecte sous une autre.

   Dix chiffres = numéro national, quel que soit le premier : les
   mobiles ivoiriens commencent par 01, 05 ou 07, les fixes par 25
   ou 27. ─────────────────────────────────────────────────── */

function normaliserTelephone(brut) {
  let v = String(brut ?? '').replace(/[^0-9]/g, '');
  if (v.startsWith('00225')) v = v.slice(2);
  if (v.length === 10) v = `225${v}`;
  return v;
}

function telephoneValide(brut) {
  const v = normaliserTelephone(brut);
  return v.length === 13 && v.startsWith('225');
}

function emailTechnique(brut) {
  return `${normaliserTelephone(brut)}@yalla.ci`;
}

/* ── Retours à l'écran ─────────────────────────────────────── */

function afficherMessage(element, texte, ton) {
  element.textContent = texte;
  element.dataset.ton = ton;
  element.hidden = false;
}

function masquerMessage(element) {
  element.hidden = true;
  element.textContent = '';
}

function occuper(bouton, occupe, libelle) {
  bouton.disabled = occupe;
  bouton.querySelector('span').textContent = libelle;
}

/* ── Onglets ───────────────────────────────────────────────── */

const ongletConnexion = document.getElementById('ongletConnexion');
const ongletInscription = document.getElementById('ongletInscription');
const voletConnexion = document.getElementById('voletConnexion');
const voletInscription = document.getElementById('voletInscription');

function basculerVers(onglet) {
  const versConnexion = onglet === 'connexion';

  ongletConnexion.classList.toggle('est-actif', versConnexion);
  ongletInscription.classList.toggle('est-actif', !versConnexion);
  ongletConnexion.setAttribute('aria-selected', String(versConnexion));
  ongletInscription.setAttribute('aria-selected', String(!versConnexion));
  voletConnexion.hidden = !versConnexion;
  voletInscription.hidden = versConnexion;

  // L'ancre garde l'onglet à travers un rechargement, et permet de pointer
  // directement sur l'inscription depuis un lien du site.
  history.replaceState(null, '', versConnexion ? '#connexion' : '#inscription');
}

ongletConnexion.addEventListener('click', () => basculerVers('connexion'));
ongletInscription.addEventListener('click', () => basculerVers('inscription'));

if (location.hash === '#inscription') basculerVers('inscription');

/* ── Mot de passe visible ──────────────────────────────────── */

const champMotDePasse = document.getElementById('connexionMotDePasse');
const boutonOeil = document.getElementById('basculerMdp');

boutonOeil.addEventListener('click', () => {
  const visible = champMotDePasse.type === 'text';
  champMotDePasse.type = visible ? 'password' : 'text';
  boutonOeil.textContent = visible ? 'Afficher' : 'Masquer';
  boutonOeil.setAttribute(
    'aria-label',
    visible ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
  );
});

/* ── Le profil décide des champs utiles ────────────────────── */

const champMarques = document.getElementById('inscriptionMarques');
const labelMarques = document.getElementById('labelMarques');
const aideMarques = document.getElementById('aideMarques');
const champCommunes = document.getElementById('champCommunes');

for (const radio of document.querySelectorAll('input[name="profil"]')) {
  radio.addEventListener('change', () => {
    const fabricant = radio.value === 'fabricant';

    // Un fabricant déclare SES marques ; un distributeur déclare celles
    // qu'il porte. Même champ, deux questions différentes : le libellé
    // change plutôt que d'ajouter un champ que l'un des deux laisserait vide.
    labelMarques.textContent = fabricant ? 'Vos marques' : 'Marques distribuées';
    aideMarques.textContent = fabricant
      ? 'Celles que vous voulez suivre sur le réseau.'
      : 'Séparez-les par des virgules.';
    champMarques.placeholder = fabricant
      ? 'Alyssa, Maman, La Rizière…'
      : 'Alyssa, Maman, Darci…';

    // Un fabricant ne dessert pas des communes, ses distributeurs le font.
    champCommunes.hidden = fabricant;
  });
}

/* ── Inscription ───────────────────────────────────────────── */

const formInscription = document.getElementById('formInscription');
const messageInscription = document.getElementById('messageInscription');
const boutonInscription = document.getElementById('boutonInscription');

formInscription.addEventListener('submit', async (evenement) => {
  evenement.preventDefault();
  masquerMessage(messageInscription);

  const donnees = new FormData(formInscription);
  const telephone = donnees.get('telephone');

  if (!donnees.get('profil')) {
    afficherMessage(messageInscription, 'Indiquez d’abord quel est votre profil.', 'erreur');
    return;
  }
  if (!telephoneValide(telephone)) {
    afficherMessage(
      messageInscription,
      'Ce numéro ne fait pas dix chiffres. Exemple : 07 06 30 30 30.',
      'erreur',
    );
    document.getElementById('inscriptionTelephone').focus();
    return;
  }

  occuper(boutonInscription, true, 'Envoi…');

  try {
    const reponse = await fetch(`${SUPABASE_URL}/rest/v1/rpc/deposer_demande_acces`, {
      method: 'POST',
      headers: { apikey: SUPABASE_CLE, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        p_profil: donnees.get('profil'),
        p_nom: donnees.get('nom'),
        p_societe: donnees.get('societe'),
        p_telephone: telephone,
        p_email: donnees.get('email') || null,
        p_ville: donnees.get('ville') || null,
        p_communes: donnees.get('communes') || null,
        p_marques: donnees.get('marques') || null,
        p_message: donnees.get('message') || null,
      }),
    });

    if (!reponse.ok) {
      const corps = await reponse.json().catch(() => ({}));
      throw new Error(corps.message || 'refus');
    }

    formInscription.reset();
    champCommunes.hidden = false;
    afficherMessage(
      messageInscription,
      'Demande reçue. L’administrateur du réseau l’examine et vous rappelle '
        + 'pour vous remettre vos identifiants. Aucun mot de passe ne circulera par '
        + 'e-mail.',
      'succes',
    );
  } catch (erreur) {
    const brut = String(erreur.message || '');
    // Les contrôles de la fonction SQL remontent leur message tel quel : ils
    // sont déjà rédigés pour être lus.
    const lisible = /numéro|Nom|société|Profil/i.test(brut)
      ? brut
      : 'Envoi impossible. Vérifiez votre connexion, puis réessayez.';
    afficherMessage(messageInscription, lisible, 'erreur');
  } finally {
    occuper(boutonInscription, false, 'Envoyer ma demande');
  }
});

/* ── Connexion ─────────────────────────────────────────────── */

const formConnexion = document.getElementById('formConnexion');
const messageConnexion = document.getElementById('messageConnexion');
const boutonConnexion = document.getElementById('boutonConnexion');

/* Le rôle n'est PAS choisi par l'utilisateur : il est inscrit dans le jeton
   par le hook d'émission de Supabase, et signé. Un sélecteur de rôle à la
   connexion serait au mieux redondant, au pire une porte ouverte. On lit donc
   la charge utile du jeton pour savoir où envoyer la personne. */
function claimsDuJeton(jeton) {
  try {
    const charge = jeton.split('.')[1];
    const normalise = charge.replace(/-/g, '+').replace(/_/g, '/');
    const texte = decodeURIComponent(
      atob(normalise)
        .split('')
        .map((c) => `%${c.charCodeAt(0).toString(16).padStart(2, '0')}`)
        .join(''),
    );
    return JSON.parse(texte);
  } catch {
    return {};
  }
}

const DESTINATIONS = {
  fabricant: 'tableau-de-bord.html',
  administrateur: 'tableau-de-bord.html',
  distributeur: 'distributeur.html',
};

const SUR_MOBILE = {
  point_de_vente: 'Votre compte est celui d’une boutique : tout se passe dans '
    + 'l’application, sur votre téléphone.',
  livreur: 'Votre compte est celui d’un livreur : les courses et le suivi de '
    + 'position sont dans l’application.',
  agent_recenseur: 'Le recensement se fait sur le terrain, depuis l’application.',
};

formConnexion.addEventListener('submit', async (evenement) => {
  evenement.preventDefault();
  masquerMessage(messageConnexion);

  const telephone = document.getElementById('connexionTelephone').value;
  const motDePasse = champMotDePasse.value;

  if (!telephoneValide(telephone)) {
    afficherMessage(
      messageConnexion,
      'Ce numéro ne fait pas dix chiffres. Exemple : 07 06 30 30 30.',
      'erreur',
    );
    return;
  }

  occuper(boutonConnexion, true, 'Connexion…');

  try {
    const reponse = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
      method: 'POST',
      headers: { apikey: SUPABASE_CLE, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: emailTechnique(telephone), password: motDePasse }),
    });
    const corps = await reponse.json();

    if (!reponse.ok || !corps.access_token) {
      // On ne répète pas le message de Supabase, qui parle d'adresse e-mail
      // alors que la personne a saisi un numéro.
      afficherMessage(messageConnexion, 'Numéro ou mot de passe incorrect.', 'erreur');
      return;
    }

    const claims = claimsDuJeton(corps.access_token);
    const role = claims.user_role;

    if (!role) {
      afficherMessage(
        messageConnexion,
        'Votre compte existe mais n’est rattaché à aucun profil. '
          + 'Contactez l’administrateur du réseau.',
        'erreur',
      );
      return;
    }

    if (SUR_MOBILE[role]) {
      afficherMessage(messageConnexion, SUR_MOBILE[role], 'succes');
      return;
    }

    const destination = DESTINATIONS[role];
    if (!destination) {
      afficherMessage(
        messageConnexion,
        'Aucun espace web ne correspond encore à votre profil.',
        'erreur',
      );
      return;
    }

    // La session tient le temps de l'onglet : un tableau de bord consulté sur
    // un poste partagé ne doit pas rester ouvert pour le suivant.
    sessionStorage.setItem('yalla.jeton', corps.access_token);
    sessionStorage.setItem('yalla.nom', claims.nom || '');
    sessionStorage.setItem('yalla.role', role);
    location.href = destination;
  } catch {
    afficherMessage(
      messageConnexion,
      'Connexion impossible. Vérifiez votre réseau, puis réessayez.',
      'erreur',
    );
  } finally {
    occuper(boutonConnexion, false, 'Entrer dans mon espace');
  }
});
