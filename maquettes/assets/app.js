/* Navigation entre écrans des maquettes.
   Chaque prototype déclare des .tab[data-go] et des .screen[data-screen] ;
   ce script fait le lien, sans dépendance. */
(() => {
  'use strict';

  const activer = (racine, nom) => {
    racine.querySelectorAll('[data-screen]').forEach(s =>
      s.classList.toggle('is-active', s.dataset.screen === nom));
    racine.querySelectorAll('[data-go]').forEach(t => {
      const actif = t.dataset.go === nom;
      t.classList.toggle('is-active', actif);
      // aria-current plutôt que aria-selected : ce sont des liens de navigation,
      // pas des onglets ARIA au sens strict.
      if (actif) t.setAttribute('aria-current', 'page');
      else t.removeAttribute('aria-current');
    });
    const corps = racine.querySelector('.body');
    if (corps) corps.scrollTop = 0;
  };

  document.querySelectorAll('[data-app]').forEach(app => {
    app.addEventListener('click', e => {
      const cible = e.target.closest('[data-go]');
      if (!cible || !app.contains(cible)) return;
      e.preventDefault();
      activer(app, cible.dataset.go);
    });

    // Écran initial : celui marqué is-active, sinon le premier.
    const depart = app.querySelector('.screen.is-active') || app.querySelector('[data-screen]');
    if (depart) activer(app, depart.dataset.screen);
  });

  // Les chips de filtre sont purement démonstratives : un seul actif par groupe.
  document.querySelectorAll('[data-chips]').forEach(groupe => {
    groupe.addEventListener('click', e => {
      const chip = e.target.closest('.chip');
      if (!chip) return;
      groupe.querySelectorAll('.chip').forEach(c => c.classList.remove('is-on'));
      chip.classList.add('is-on');
    });
  });
})();
