(() => {
  const key = 'audience-v1';
  const id = '';
  const configured = /^G-[A-Z0-9]+$/.test(id);
  const maxAge = 180 * 24 * 60 * 60;
  const secure = location.protocol === 'https:' ? '; Secure' : '';
  let choice = document.cookie.match(/(?:^|;\s*)audience-v1=(yes|no)(?:;|$)/)?.[1] ?? null;
  const privacyUrl = new URL('confidentialite.html', document.currentScript.src);

  if (configured) window[`ga-disable-${id}`] = choice !== 'yes';

  function start() {
    if (!configured || choice !== 'yes' || document.querySelector('#audience-tag')) return;
    window[`ga-disable-${id}`] = false;
    window.dataLayer = window.dataLayer || [];
    window.gtag = function () { window.dataLayer.push(arguments); };
    window.gtag('js', new Date());
    window.gtag('config', id, {
      allow_google_signals: false,
      allow_ad_personalization_signals: false,
      cookie_domain: 'none',
      page_location: location.origin + location.pathname,
      page_referrer: ''
    });
    const tag = document.createElement('script');
    tag.id = 'audience-tag';
    tag.async = true;
    tag.src = `https://www.googletagmanager.com/gtag/js?id=${id}`;
    document.head.append(tag);
  }

  const panel = document.createElement('section');
  panel.className = 'consent-panel';
  panel.setAttribute('role', 'region');
  panel.setAttribute('aria-labelledby', 'consent-title');
  panel.innerHTML = `
    <h2 id="consent-title">Ce site utilise des cookies</h2>
    <div class="consent-panel__layout">
      <div class="consent-panel__content">
        <p id="consent-description">Nous utilisons des cookies essentiels au fonctionnement du site. Avec votre autorisation, nous pouvons aussi utiliser des cookies de mesure d’audience. ${configured
          ? 'Vous pouvez modifier votre choix à tout moment.'
          : 'La mesure d’audience est actuellement désactivée sur ce site.'}
          <a href="${privacyUrl.href}">En savoir plus</a>.
        </p>
        <div class="consent-panel__preferences">
          <label class="consent-toggle">
            <span>Essentiels</span>
            <input type="checkbox" checked disabled aria-label="Cookies essentiels, toujours actifs">
          </label>
          <label class="consent-toggle">
            <span>Mesure d’audience</span>
            <input id="consent-audience" type="checkbox" ${choice === 'yes' ? 'checked' : ''}>
          </label>
          <details class="consent-details">
            <summary>Afficher les détails</summary>
            <div class="consent-details__content">
              <p><strong>Essentiels</strong> — mémorisent votre choix et permettent au site de fonctionner. Ils sont toujours actifs.</p>
              <p><strong>Mesure d’audience</strong> — ${configured
                ? 'aide Yalla à comprendre la fréquentation du site et ne démarre qu’avec votre accord.'
                : 'aucun outil de mesure n’est actuellement actif ; aucun cookie de mesure ne sera déposé.'}</p>
            </div>
          </details>
        </div>
      </div>
      <div class="consent-panel__actions">
        <button type="button" data-choice="yes">Tout autoriser</button>
        <button type="button" data-choice="selection">Autoriser la sélection</button>
        <button type="button" data-choice="no">Refuser</button>
      </div>
    </div>`;
  panel.hidden = Boolean(choice);
  panel.tabIndex = -1;
  document.body.append(panel);

  let opener;
  document.addEventListener('click', event => {
    const button = event.target.closest('[data-cookie-settings]');
    if (!button) return;
    opener = button;
    panel.querySelector('#consent-audience').checked = choice === 'yes';
    panel.hidden = false;
    panel.focus();
  });

  panel.addEventListener('click', event => {
    const button = event.target.closest('[data-choice]');
    if (!button) return;

    const wasTracking = choice === 'yes' && configured;
    choice = button.dataset.choice === 'selection'
      ? (panel.querySelector('#consent-audience').checked ? 'yes' : 'no')
      : button.dataset.choice;
    document.cookie = `${key}=${choice}; Max-Age=${maxAge}; Path=/; SameSite=Lax${secure}`;
    panel.hidden = true;
    opener?.focus();

    if (choice === 'no' && wasTracking) {
      window[`ga-disable-${id}`] = true;
      for (const name of document.cookie.split(';').map(part => part.trim().split('=')[0])) {
        if (/^_ga(?:_[A-Z0-9]+)?$/.test(name)) {
          document.cookie = `${name}=; Max-Age=0; Path=/${secure}`;
        }
      }
      location.reload();
      return;
    }

    start();
  });

  start();
})();
