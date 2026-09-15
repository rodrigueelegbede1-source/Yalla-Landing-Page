/* ═══════════════════════════════════════════════════════════
   YALLA — Landing page
   Interactions : reveals, progression, flux temps réel,
   compteurs, tracé SVG, tilt, magnétisme, menu mobile.
   ═══════════════════════════════════════════════════════════ */

(() => {
  'use strict';

  // Les états "cachés" (reveals, rideau du titre) ne s'appliquent que si JS tourne :
  // sans script, la page reste entièrement lisible au lieu de rester blanche.
  document.documentElement.classList.add('js');

  const REDUCED = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const COARSE  = window.matchMedia('(pointer: coarse)').matches;
  const $  = (s, c = document) => c.querySelector(s);
  const $$ = (s, c = document) => [...c.querySelectorAll(s)];
  const clamp = (v, a, b) => Math.min(Math.max(v, a), b);

  /* ─────────────── 1. Entrée de page ─────────────── */
  const boot = () => document.body.classList.add('is-ready');
  if (document.readyState === 'complete') requestAnimationFrame(boot);
  else window.addEventListener('load', () => requestAnimationFrame(boot));
  // Filet de sécurité : si les polices tardent, on lance quand même.
  setTimeout(boot, 1200);

  /* ─────────────── 2. Année du footer ─────────────── */
  const year = $('#year');
  if (year) year.textContent = String(new Date().getFullYear());

  /* ─────────────── 3. Nav : état scrollé + masquage ─────────────── */
  const nav  = $('#nav');
  const bar  = $('#progressBar');
  let lastY  = window.scrollY;
  let ticking = false;

  const onScroll = () => {
    const y   = window.scrollY;
    const max = document.documentElement.scrollHeight - window.innerHeight;

    if (bar) bar.style.width = `${clamp((y / (max || 1)) * 100, 0, 100)}%`;

    if (nav) {
      nav.classList.toggle('is-scrolled', y > 24);
      // On masque la nav en descente rapide, on la rend en montée.
      const goingDown = y > lastY && y > 420;
      if (!$('#mobileMenu')?.classList.contains('is-open')) {
        nav.classList.toggle('is-hidden', goingDown);
      }
    }
    lastY = y;
    ticking = false;
  };

  window.addEventListener('scroll', () => {
    if (!ticking) { ticking = true; requestAnimationFrame(onScroll); }
  }, { passive: true });
  onScroll();

  /* ─────────────── 4. Menu mobile ─────────────── */
  const burger = $('#burger');
  const menu   = $('#mobileMenu');

  const setMenu = (open) => {
    if (!menu || !burger) return;
    menu.classList.toggle('is-open', open);
    burger.classList.toggle('is-open', open);
    burger.setAttribute('aria-expanded', String(open));
    burger.setAttribute('aria-label', open ? 'Fermer le menu' : 'Ouvrir le menu');
    document.body.classList.toggle('is-locked', open);
    if (open) menu.removeAttribute('inert'); else menu.setAttribute('inert', '');
    if (open) nav?.classList.remove('is-hidden');
  };

  burger?.addEventListener('click', () => setMenu(!menu.classList.contains('is-open')));
  $$('#mobileMenu a').forEach(a => a.addEventListener('click', () => setMenu(false)));
  document.addEventListener('keydown', e => { if (e.key === 'Escape') setMenu(false); });

  /* ─────────────── 5. Reveals au scroll ─────────────── */
  const HAS_IO = 'IntersectionObserver' in window;

  if (!HAS_IO) {
    // Navigateur ancien : on affiche tout d'un coup plutôt que rien.
    $$('.reveal, .card').forEach(el => el.classList.add('is-in'));
  } else {
    const revealIO = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('is-in');
        revealIO.unobserve(entry.target);
      });
    }, { threshold: 0.15, rootMargin: '0px 0px -8% 0px' });

    $$('.reveal, .card').forEach(el => revealIO.observe(el));
  }

  /* ─────────────── 6. Compteurs ─────────────── */
  const runCount = (el) => {
    const target = parseFloat(el.dataset.count);
    const suffix = el.dataset.suffix || '';
    if (Number.isNaN(target)) return;
    if (REDUCED) { el.textContent = target + suffix; return; }

    const dur = 1300;
    const t0  = performance.now();
    const tick = (now) => {
      const p = clamp((now - t0) / dur, 0, 1);
      const eased = 1 - Math.pow(1 - p, 4);          // easeOutQuart
      el.textContent = Math.round(target * eased) + suffix;
      if (p < 1) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  };

  if (!HAS_IO) {
    $$('[data-count]').forEach(runCount);
  } else {
    const countIO = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (!entry.isIntersecting) return;
        runCount(entry.target);
        countIO.unobserve(entry.target);
      });
    }, { threshold: 0.6 });

    $$('[data-count]').forEach(el => countIO.observe(el));
  }

  /* ─────────────── 7. Tracé de la ligne des étapes ─────────────── */
  const path    = $('#stepsPath');
  const stepsEl = $('.steps');

  if (path && stepsEl && !REDUCED) {
    const len = path.getTotalLength();
    path.style.strokeDasharray  = `${len}`;
    path.style.strokeDashoffset = `${len}`;

    let raf = null;
    const drawLine = () => {
      raf = null;
      const r  = stepsEl.getBoundingClientRect();
      const vh = window.innerHeight;
      // Progression : du moment où la section entre à 85% jusqu'à sa moitié haute.
      const p  = clamp((vh * 0.85 - r.top) / (vh * 0.62), 0, 1);
      path.style.strokeDashoffset = `${len * (1 - p)}`;
    };

    window.addEventListener('scroll', () => {
      if (!raf) raf = requestAnimationFrame(drawLine);
    }, { passive: true });
    window.addEventListener('resize', drawLine);
    drawLine();
  } else if (path) {
    path.style.opacity = '.35';
  }

  /* ─────────────── 8. Flux de signalements (démo) ─────────────── */
  const feedList = $('#feedList');

  if (feedList) {
    const SIGNALS = [
      { p: 'Lait concentré 400g',  b: 'SUPÉRETTE LA GRÂCE · COCODY' },
      { p: 'Sucre en morceaux 1kg', b: 'BOUTIQUE AWA · YOPOUGON' },
      { p: 'Eau minérale 1,5L',     b: 'KIOSQUE ODIENNÉ · TREICHVILLE' },
      { p: 'Huile végétale 5L',     b: 'ALIMENTATION BÉNÉDICTION · MARCORY' },
      { p: 'Boisson gazeuse 33cl',  b: 'MAQUIS LE BAOBAB · ABOBO' },
      { p: 'Riz parfumé 25kg',      b: 'SUPÉRETTE CENTRALE · PLATEAU' },
      { p: 'Café soluble 100g',     b: 'BOUTIQUE ZANZAN · ADJAMÉ' },
      { p: 'Savon de ménage',       b: 'KIOSQUE BONHEUR · KOUMASSI' }
    ];

    const MAX = 3;
    let idx = 0;

    const makeItem = (s, secs) => {
      const el = document.createElement('div');
      el.className = 'feed-item';
      el.innerHTML =
        '<span class="feed-item__dot"></span>' +
        `<span class="feed-item__txt"><b></b><i></i></span>` +
        `<span class="feed-item__t">${secs}s</span>`;
      // textContent : les libellés restent des données, jamais du balisage.
      el.querySelector('b').textContent = s.p;
      el.querySelector('i').textContent = s.b;
      return el;
    };

    const push = () => {
      const s = SIGNALS[idx % SIGNALS.length];
      idx++;
      feedList.prepend(makeItem(s, Math.floor(Math.random() * 40) + 3));

      // Sortie animée du plus ancien : on le retire du flux tout de suite
      // pour que le compte reste juste, la suppression du nœud suit.
      [...feedList.children].slice(MAX).forEach(old => {
        old.classList.add('is-out');
        setTimeout(() => old.remove(), 450);
      });
    };

    // Amorçage
    for (let i = 0; i < MAX; i++) {
      const s = SIGNALS[idx++ % SIGNALS.length];
      feedList.appendChild(makeItem(s, (i + 1) * 12 + 4));
    }

    if (!REDUCED && HAS_IO) {
      let timer = null;
      const start = () => { if (!timer) timer = setInterval(push, 3200); };
      const stop  = () => { clearInterval(timer); timer = null; };

      // On n'anime que si le téléphone est visible, et jamais en arrière-plan.
      const deviceIO = new IntersectionObserver(([e]) => e.isIntersecting ? start() : stop(), { threshold: 0.2 });
      const device = $('#device');
      if (device) deviceIO.observe(device);
      document.addEventListener('visibilitychange', () => document.hidden ? stop() : start());
    }
  }

  /* ─────────────── 9. Tilt du téléphone ─────────────── */
  const tiltEl = $('[data-tilt]');

  if (tiltEl && !REDUCED && !COARSE) {
    const host = $('#device');
    let rafT = null, tx = 0, ty = 0;

    const apply = () => {
      rafT = null;
      tiltEl.style.transform = `rotateY(${tx}deg) rotateX(${ty}deg) translateZ(0)`;
    };

    host?.addEventListener('pointermove', (e) => {
      const r = host.getBoundingClientRect();
      tx = ((e.clientX - r.left) / r.width  - 0.5) * 13;
      ty = ((e.clientY - r.top)  / r.height - 0.5) * -9;
      if (!rafT) rafT = requestAnimationFrame(apply);
    });

    host?.addEventListener('pointerleave', () => {
      tx = 0; ty = 0;
      if (!rafT) rafT = requestAnimationFrame(apply);
    });
  }

  /* ─────────────── 10. Spotlight des cartes ─────────────── */
  if (!COARSE) {
    $$('[data-spot]').forEach(card => {
      card.addEventListener('pointermove', (e) => {
        const r = card.getBoundingClientRect();
        card.style.setProperty('--mx', `${e.clientX - r.left}px`);
        card.style.setProperty('--my', `${e.clientY - r.top}px`);
      });
    });
  }

  /* ─────────────── 11. Boutons magnétiques ─────────────── */
  if (!REDUCED && !COARSE) {
    $$('[data-magnetic]').forEach(btn => {
      let rafM = null, mx = 0, my = 0;

      const move = () => { rafM = null; btn.style.transform = `translate(${mx}px, ${my}px)`; };

      btn.addEventListener('pointermove', (e) => {
        const r = btn.getBoundingClientRect();
        mx = (e.clientX - (r.left + r.width  / 2)) * 0.22;
        my = (e.clientY - (r.top  + r.height / 2)) * 0.3;
        if (!rafM) rafM = requestAnimationFrame(move);
      });

      btn.addEventListener('pointerleave', () => {
        mx = 0; my = 0;
        if (!rafM) rafM = requestAnimationFrame(move);
      });
    });
  }

  /* ─────────────── 12. Parallaxe douce du halo ─────────────── */
  const glowA = $('.hero__glow--a');
  const hero  = $('#hero');

  if (glowA && hero && !REDUCED) {
    let rafP = null;
    const move = () => {
      rafP = null;
      const y = window.scrollY;
      if (y > window.innerHeight * 1.2) return;
      glowA.style.translate = `0 ${y * 0.16}px`;
    };
    window.addEventListener('scroll', () => { if (!rafP) rafP = requestAnimationFrame(move); }, { passive: true });
  }

  /* ─────────────── 13. Ancres : compensation de la nav fixe ─────────────── */
  $$('a[href^="#"]').forEach(a => {
    a.addEventListener('click', (e) => {
      const id = a.getAttribute('href');
      if (!id || id === '#') return;
      const target = document.querySelector(id);
      if (!target) return;

      e.preventDefault();
      const top = target.getBoundingClientRect().top + window.scrollY - 72;
      window.scrollTo({ top, behavior: REDUCED ? 'auto' : 'smooth' });
      history.replaceState(null, '', id);
    });
  });


  /* ─────────────── 14. Formulaire « rejoindre le réseau » ─────────────── */
  const leadForm = $("#leadForm");

  if (leadForm) {
    const note = $("#leadNote");

    const RULES = {
      "f-nom":    v => v.trim().length >= 2      || "Indiquez votre nom",
      "f-profil": v => v !== ""                  || "Choisissez votre profil",
      // Numéros ivoiriens : 8 à 15 chiffres une fois les séparateurs retirés.
      "f-tel":    v => /^[0-9]{8,15}$/.test(v.replace(/[\s.+()\-]/g, "")) || "Numéro invalide",
    };

    const check = (el) => {
      const rule = RULES[el.id];
      if (!rule) return true;
      const res = rule(el.value);
      const field = el.closest(".field");
      const err = field.querySelector(".field__err");
      const ok = res === true;
      field.classList.toggle("is-invalid", !ok);
      if (err) err.textContent = ok ? "" : res;
      return ok;
    };

    // On ne valide au fil de la frappe qu'après une première erreur : sinon
    // le champ passe en rouge dès le premier caractère saisi.
    Object.keys(RULES).forEach(id => {
      const el = document.getElementById(id);
      if (!el) return;
      el.addEventListener("blur", () => check(el));
      el.addEventListener("input", () => {
        if (el.closest(".field").classList.contains("is-invalid")) check(el);
      });
    });

    leadForm.addEventListener("submit", (e) => {
      e.preventDefault();

      const champs = Object.keys(RULES).map(id => document.getElementById(id)).filter(Boolean);
      // On valide tous les champs avant de sortir : l'utilisateur voit d'un coup
      // tout ce qui bloque, au lieu de les corriger un par un.
      const invalides = champs.filter(el => !check(el));
      if (invalides.length) { invalides[0].focus(); return; }

      const val = (n) => (leadForm.elements[n] && leadForm.elements[n].value.trim()) || "—";
      const corps = [
        "Nom : "       + val("nom"),
        "Profil : "    + val("profil"),
        "Téléphone : " + val("telephone"),
        "",
        "Message :",
        val("message"),
      ].join("\n");

      // Pas de backend sur une page statique : on ouvre le client mail de
      // l'utilisateur, pré-rempli. À remplacer par un POST le jour où une API existe.
      const url = "mailto:contact@yalla.ci"
        + "?subject=" + encodeURIComponent("Demande via le site — " + val("profil"))
        + "&body="    + encodeURIComponent(corps);

      window.location.href = url;

      if (note) {
        note.textContent = "VOTRE MESSAGERIE S'OUVRE AVEC LA DEMANDE PRÉ-REMPLIE";
        note.classList.add("is-ok");
      }
    });
  }

  /* ─────────────── 12. La chaîne : cas de figure et maillons ───────────────
     Trois configurations réelles de la distribution ivoirienne. Le schéma se
     reconfigure, et chaque maillon ouvre le détail de son interface.
     Sans JS : le cas 01 reste affiché et les six panneaux s'empilent — la
     section reste lisible, elle perd seulement l'interaction. */
  const chainFlow = $('#chainFlow');
  if (chainFlow) {
    const NOTES = {
      complete:    "LE FABRICANT CONFIE LA DISTRIBUTION À DES GROSSISTES AFFILIÉS · CHACUN PILOTE SES PROPRES LIVREURS",
      independant: "LE DISTRIBUTEUR TRAVAILLE SANS FABRICANT ATTITRÉ · IL SERT LES BOUTIQUES AVEC SES PROPRES LIVREURS",
      integre:     "LE FABRICANT ASSURE LUI-MÊME SA DISTRIBUTION · SES LIVREURS LUI SONT DIRECTEMENT RATTACHÉS",
    };

    const note   = $('#chainNote');
    const cases  = $$('.chain__case');
    const links  = $$('.link');
    const panels = $$('.chain__panel');

    cases.forEach((btn) => {
      btn.addEventListener('click', () => {
        const key = btn.dataset.case;
        if (!key) return;
        cases.forEach((b) => {
          const on = b === btn;
          b.classList.toggle('is-active', on);
          b.setAttribute('aria-selected', String(on));
        });
        chainFlow.dataset.case = key;
        if (note && NOTES[key]) note.textContent = NOTES[key];
      });
    });

    const showRole = (role) => {
      if (!role) return;
      links.forEach((l) => {
        const on = l.dataset.role === role;
        l.classList.toggle('is-active', on);
        l.setAttribute('aria-pressed', String(on));
      });
      panels.forEach((p) => p.classList.toggle('is-shown', p.dataset.panel === role));
    };

    links.forEach((l) => l.addEventListener('click', () => showRole(l.dataset.role)));

    // Le point de vente ouvre la section : c'est lui qui déclenche toute la chaîne.
    showRole('point-de-vente');
  }

})();
