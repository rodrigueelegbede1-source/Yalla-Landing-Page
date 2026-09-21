/* ═══════════════════════════════════════════════════════════
   YALLA — Téléchargement depuis la page d'accueil

   Un clic sur « Télécharger l'application » doit lancer le
   fichier tout de suite, sans page intermédiaire.

   POURQUOI LA PAGE S'OUVRE QUAND MÊME, JUSTE APRÈS. Yalla n'est
   pas sur le Play Store, et Android bloque par défaut ce qui
   vient d'ailleurs : au moment d'ouvrir le fichier, l'utilisateur
   voit « Installation bloquée » et s'arrête là s'il ne sait pas
   quoi faire. Le téléchargement part donc immédiatement, comme
   demandé, ET les instructions d'installation s'affichent pendant
   que le fichier descend. Les deux choses arrivent, dans le bon
   ordre.

   SANS JAVASCRIPT, le lien mène simplement à cette page, qui
   lance elle-même le téléchargement. Rien n'est cassé.
   ═══════════════════════════════════════════════════════════ */

(() => {
  // Les deux boutons de la page, celui du hero et celui du bas : un visiteur
  // qui clique sur « Télécharger » attend la même chose aux deux endroits.
  const liens = document.querySelectorAll('a[href="telechargement.html"]');
  const base = window.YALLA_CONFIG?.url;
  if (!liens.length || !base) return;

  const FICHIER = `${base}/storage/v1/object/public/application/yalla.apk`;

  // Sur un appareil qui n'est pas Android, télécharger un APK n'a aucun
  // intérêt : le fichier restera inutilisable. On laisse alors le lien mener à
  // la page, qui l'explique, plutôt que d'imposer trente-six méga-octets pour
  // rien.
  if (!/android/i.test(navigator.userAgent)) return;

  for (const lien of liens) {
    lien.href = FICHIER;
    lien.setAttribute('download', 'yalla.apk');

    lien.addEventListener('click', () => {
      // Le navigateur télécharge le fichier sans quitter la page : on peut
      // donc enchaîner sur les instructions. Le court délai laisse le
      // téléchargement démarrer avant que la navigation ne change de document.
      //
      // Le drapeau évite que la page d'arrivée ne relance un second
      // téléchargement : elle vérifie la même clé avant de se déclencher.
      sessionStorage.setItem('yalla.telechargement', '1');
      setTimeout(() => { location.href = 'telechargement.html'; }, 600);
    });
  }
})();
