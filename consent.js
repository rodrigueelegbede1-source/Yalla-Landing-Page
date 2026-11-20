(() => {
  const key = 'audience-v1';
  const id = '';
  const configured = /^G-[A-Z0-9]+$/.test(id);
  const maxAge = 180 * 24 * 60 * 60;
  const secure = location.protocol === 'https:' ? '; Secure' : '';
  let choice = document.cookie.match(/(?:^|;\s*)audience-v1=(yes|no)(?:;|$)/)?.[1];
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
  panel.setAttribute('aria-labelledby', 'consent-title');
  panel.innerHTML = `<h2 id="consent-title">Préférences de cookies</h2>
    <p>Un cookie mémorise votre choix pendant six mois. ${configured
      ? 'Les cookies de mesure d’audience ne sont déposés qu’avec votre accord.'
      : 'La mesure d’audience est désactivée sur ce site.'}
    <a href="${new URL('confidentialite.html', document.currentScript.src)}">Politique de confidentialité</a>.</p>
    <div><button type="button" value="no">${configured ? 'Refuser' : 'Fermer'}</button>
    ${configured ? '<button type="button" value="yes">Accepter la mesure d’audience</button>' : ''}</div>`;
  panel.hidden = Boolean(choice);
  panel.tabIndex = -1;
  document.body.append(panel);
  let opener;
  document.addEventListener('click', event => {
    const button = event.target.closest('[data-cookie-settings]');
    if (!button) return;
    opener = button;
    panel.hidden = false;
    panel.focus();
  });
  panel.addEventListener('click', event => {
    const button = event.target.closest('button');
    if (!button) return;
    const wasTracking = choice === 'yes' && configured;
    choice = button.value;
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
