/* ═══════════════════════════════════════════════════════════
   YALLA — Téléchargement de l'application

   Le fichier est servi depuis Supabase Storage et non depuis le
   site : un binaire de plusieurs dizaines de méga-octets dans le
   dépôt serait retransféré à chaque déploiement, et Git n'est pas
   fait pour ça.

   Le téléchargement part tout seul, comme demandé, mais le bouton
   reste : un démarrage automatique est bloqué par certains
   navigateurs, et une page qui semble ne rien faire perd son
   visiteur.
   ═══════════════════════════════════════════════════════════ */

const BASE = window.YALLA_CONFIG?.url ?? '';
const FICHIER = `${BASE}/storage/v1/object/public/application/yalla.apk`;

const bouton = document.getElementById('boutonTelecharger');
const message = document.getElementById('messageTelechargement');
const detail = document.getElementById('detailFichier');

bouton.href = FICHIER;

function informer(texte, ton) {
  message.textContent = texte;
  message.dataset.ton = ton;
  message.hidden = false;
}

/* Sur un appareil qui n'est pas Android, télécharger un APK n'a aucun intérêt :
   le fichier restera inutilisable. On le dit avant, plutôt que de laisser
   quelqu'un attendre cinquante méga-octets pour rien. */
const estAndroid = /android/i.test(navigator.userAgent);

if (!estAndroid) {
  informer(
    'Cette application est pour Android. Sur iPhone ou sur ordinateur, le '
    + 'fichier ne s’installera pas. Ouvrez cette page depuis le téléphone qui '
    + 'servira en boutique.',
    'erreur',
  );
}

/* La taille réelle du fichier, demandée au serveur plutôt qu'écrite en dur :
   elle change à chaque version, et un chiffre faux sur cette page érode la
   confiance juste avant l'installation. */
(async () => {
  try {
    const reponse = await fetch(FICHIER, { method: 'HEAD' });
    if (!reponse.ok) throw new Error(String(reponse.status));

    const octets = Number(reponse.headers.get('content-length'));
    if (octets > 0) {
      const mo = (octets / 1048576).toFixed(0);
      detail.textContent = `Android 5.0 ou plus récent · ${mo} Mo`;
    }
  } catch {
    informer(
      'Le fichier n’est pas disponible pour le moment. Réessayez dans quelques '
      + 'minutes, ou demandez-le à la personne qui vous a recensé.',
      'erreur',
    );
    bouton.setAttribute('aria-disabled', 'true');
    return;
  }

  // Démarrage automatique, une seule fois, et seulement sur Android.
  if (estAndroid && !sessionStorage.getItem('yalla.telechargement')) {
    sessionStorage.setItem('yalla.telechargement', '1');
    bouton.click();
  }
})();
