(function () {
  var root = document.documentElement;
  var dark = window.matchMedia('(prefers-color-scheme: dark)');
  var still = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  function $$(s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); }

  // ---- Theme: the button overrides the system, and the screenshots follow it.
  function theme() { return root.getAttribute('data-theme') || (dark.matches ? 'dark' : 'light'); }
  function syncShots() {
    var t = root.getAttribute('data-theme');
    var m = t === 'dark' ? 'all' : t === 'light' ? 'not all' : '(prefers-color-scheme: dark)';
    $$('source[data-dark]').forEach(function (s) { s.media = m; });
  }
  $$('.theme-btn').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var next = theme() === 'dark' ? 'light' : 'dark';
      // Picking what the system already shows goes back to following it.
      if ((next === 'dark') === dark.matches) {
        root.removeAttribute('data-theme');
        try { localStorage.removeItem('theme'); } catch (e) {}
      } else {
        root.setAttribute('data-theme', next);
        try { localStorage.setItem('theme', next); } catch (e) {}
      }
      syncShots();
    });
  });
  syncShots();

  // ---- Platform: shortcuts and the download button.
  var ua = navigator.userAgent;
  var plat = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || '';
  var mobile = /Android|iPhone|iPad|iPod/i.test(ua) || (/Mac/i.test(plat) && navigator.maxTouchPoints > 1);
  var os = mobile ? null : /Mac/i.test(plat) ? 'mac' : /Win/i.test(plat) ? 'win' : /Linux|X11/i.test(plat + ua) ? 'linux' : null;
  if (os && os !== 'mac') {
    $$('kbd').forEach(function (k) { k.textContent = k.textContent.replace('⌘', 'Ctrl+').replace('⌥', 'Alt+').replace('⇧', 'Shift+'); });
  }
  var card = os && document.querySelector('.dl [data-os="' + os + '"]');
  var get = document.getElementById('get');
  if (card && get) {
    var names = { mac: 'macOS', win: 'Windows', linux: 'Linux' };
    card.classList.add('mine');
    var main = card.querySelector('.tag');
    var label = main.dataset.label;
    var others = $$('a[data-short]', card).filter(function (a) { return !a.closest('[data-arch]'); });
    var arm = card.querySelector('[data-arch="arm64"]');
    var show = function () {
      get.href = main.href;
      get.querySelector('span').textContent = 'Download for ' + names[os];
      // What the button gives, then the platform's other files: "For Apple Silicon (or Intel)".
      document.getElementById('get-sub').innerHTML = label +
        (others.length ? ' (or ' + others.map(function (a) { return '<a href="' + a.href + '">' + a.dataset.short + '</a>'; }).join(', ') + ')' : '') +
        ' · free and open source · <a href="#download">Other platforms</a>';
    };
    // An arm64 Linux gets the arm64 files; a Mac's user agent says Intel either way, so the Mac is left alone.
    if (os === 'linux' && arm && /aarch64|arm64|armv8/i.test(ua + ' ' + plat)) {
      others = $$('a[data-short]', arm);
      main = others.shift();
      label = label.replace('amd64', 'arm64');
    }
    show();
    // Windows on Arm says x64 in its user agent; Chromium's client hints tell. The button stays the x64
    // installer, which runs there emulated and is in every release, and the native zip comes first after it.
    if (os === 'win' && arm && navigator.userAgentData && navigator.userAgentData.getHighEntropyValues) {
      navigator.userAgentData.getHighEntropyValues(['architecture']).then(function (v) {
        if (v.architecture !== 'arm') return;
        others = $$('a[data-short]', arm).concat(others);
        show();
      }, function () {});
    }
  }

  // ---- Screenshot tabs: a list beside the picture, each tab carrying its figure's caption, with arrow keys.
  //      Without script every screenshot shows with its caption, one under the other.
  $$('.tour [role="tablist"]').forEach(function (list) {
    var tabs = $$('[role="tab"]', list);
    tabs.forEach(function (b) {
      var cap = document.getElementById(b.getAttribute('aria-controls')).querySelector('figcaption');
      if (!cap) return;
      var d = document.createElement('span');
      d.className = 'desc';
      d.innerHTML = cap.innerHTML;
      b.appendChild(d);
    });
    function select(b, focus) {
      if (b.hasAttribute('data-more')) fold(true);
      tabs.forEach(function (o) {
        var on = o === b;
        o.setAttribute('aria-selected', on);
        o.tabIndex = on ? 0 : -1;
        document.getElementById(o.getAttribute('aria-controls')).classList.toggle('on', on);
      });
      if (focus) { b.focus(); b.scrollIntoView({ block: 'nearest', inline: 'nearest' }); }
    }
    // The ten views behind Ten more views show when asked for, or when one of them is chosen.
    var tour = list.closest('.tour'), more = tour && tour.querySelector('.tabs-more');
    var fold = function (open) { if (!more) return; tour.classList.toggle('folded', !open); more.setAttribute('aria-expanded', String(open)); };
    if (more) { fold(false); more.addEventListener('click', function () { fold(tour.classList.contains('folded')); }); }
    tabs.forEach(function (b, i) {
      b.addEventListener('click', function () { select(b); });
      b.addEventListener('keydown', function (e) {
        var j = (e.key === 'ArrowRight' || e.key === 'ArrowDown') ? i + 1 : (e.key === 'ArrowLeft' || e.key === 'ArrowUp') ? i - 1 : e.key === 'Home' ? 0 : e.key === 'End' ? tabs.length - 1 : null;
        if (j === null) return;
        e.preventDefault();
        select(tabs[(j + tabs.length) % tabs.length], true);
      });
    });
  });
  // A link with data-tab picks that tab here; one from the other page arrives as ?tab=.
  $$('a[data-tab]').forEach(function (a) {
    a.addEventListener('click', function (e) {
      var b = document.getElementById(a.dataset.tab);
      if (!b) return;
      e.preventDefault();
      b.click();
      b.closest('section').scrollIntoView({ behavior: still ? 'auto' : 'smooth', block: 'start' });
    });
  });
  var want = new URLSearchParams(location.search).get('tab');
  if (want && document.getElementById(want)) document.getElementById(want).click();

  // ---- Copy buttons on the shell blocks.
  $$('.codeblock').forEach(function (c) {
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'copy';
    b.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></svg><span>Copy</span>';
    b.addEventListener('click', function () {
      if (!navigator.clipboard) return;
      navigator.clipboard.writeText(c.querySelector('pre').textContent).then(function () {
        b.classList.add('done');
        b.querySelector('span').textContent = 'Copied';
        setTimeout(function () { b.classList.remove('done'); b.querySelector('span').textContent = 'Copy'; }, 1600);
      });
    });
    c.appendChild(b);
  });

  // ---- The bar: the same links on both pages. The link of the section in view is underlined (a section
  //      in the submenu underlines All features and is marked in the list); with none in view, the link to
  //      this page itself (All features on the features page).
  var bar = document.querySelector('.bar');
  var all = $$('.bar .sections a');
  var top = function (a) { var h = a.closest('.has-sub'); return a.closest('.sub') ? h.querySelector(':scope > a') : a; };
  var here = function (a) { return a.pathname.replace(/index\.html$/, '') === location.pathname.replace(/index\.html$/, ''); };
  var secLinks = all.filter(function (a) { return a.hash && here(a) && document.getElementById(a.hash.slice(1)); });
  var pageLink = all.filter(function (a) { return !a.hash && here(a); })[0] || null;
  if (all.length) {
    var mark = function () {
      var y = window.innerHeight * 0.4, on = null;
      secLinks.forEach(function (a) { var r = document.getElementById(a.hash.slice(1)).getBoundingClientRect(); if (r.top <= y && r.bottom > y) on = a; });
      var lit = [];
      if (on) { lit.push(on); if (top(on) !== on) lit.push(top(on)); } else if (pageLink) lit.push(pageLink);
      all.forEach(function (a) { if (lit.indexOf(a) >= 0) a.setAttribute('aria-current', a === pageLink && !on ? 'page' : 'true'); else a.removeAttribute('aria-current'); });
    };
    window.addEventListener('scroll', mark, { passive: true });
    mark();
  }
  // The submenu: hover and focus open it in CSS; the arrow opens and shuts it for touch and keyboard.
  $$('.has-sub').forEach(function (h) {
    var t = h.querySelector('.sub-toggle');
    var set = function (open) { h.classList.toggle('open', open); h.classList.toggle('shut', !open && h.matches(':hover, :focus-within')); t.setAttribute('aria-expanded', String(open)); };
    t.addEventListener('click', function () { set(!h.classList.contains('open')); });
    h.addEventListener('mouseleave', function () { h.classList.remove('shut'); if (!h.contains(document.activeElement)) set(false); });
    h.addEventListener('focusout', function (e) { if (!h.contains(e.relatedTarget)) { set(false); h.classList.remove('shut'); } });
    h.addEventListener('keydown', function (e) { if (e.key === 'Escape') { set(false); t.focus(); } });
    $$('.sub a', h).forEach(function (a) { a.addEventListener('click', function () { set(false); if (document.activeElement) document.activeElement.blur(); }); });
    document.addEventListener('click', function (e) { if (!h.contains(e.target)) set(false); });
  });

  // ---- The bar's action steps aside while another button to the same place is on the screen.
  var cta = bar && bar.querySelector('.bar-cta');
  var twins = $$('[data-twin]');
  if (cta && twins.length && 'IntersectionObserver' in window) {
    var seen = new Set();
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) seen.add(e.target); else seen.delete(e.target); });
      bar.classList.toggle('cta-on', seen.size === 0);
    });
    twins.forEach(function (t) { io.observe(t); });
  } else if (bar) {
    bar.classList.add('cta-on');
  }

  // ---- The menu: the section names full-screen on the ink.
  var menuBtn = document.querySelector('.menu-btn');
  var panel = document.getElementById('menu');
  if (menuBtn && panel) {
    var closeBtn = panel.querySelector('.menu-close');
    var open = function () { panel.hidden = false; menuBtn.setAttribute('aria-expanded', 'true'); document.body.style.overflow = 'hidden'; closeBtn.focus(); };
    var close = function () { panel.hidden = true; menuBtn.setAttribute('aria-expanded', 'false'); document.body.style.overflow = ''; menuBtn.focus(); };
    menuBtn.addEventListener('click', open);
    closeBtn.addEventListener('click', close);
    $$('a', panel).forEach(function (a) { a.addEventListener('click', function () { panel.hidden = true; menuBtn.setAttribute('aria-expanded', 'false'); document.body.style.overflow = ''; }); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && !panel.hidden) close(); });
  }

  // ---- Pictures below the fold open from a window, and the heads, rows and cards under it rise into place, once.
  var pics = $$('[data-reveal]');
  if (!still) {
    $$('.sechead, .flist li, .story, .facts > div, .dl .card, .install, .foot-side').forEach(function (el) {
      if (el.getBoundingClientRect().top <= window.innerHeight) return;
      el.classList.add('rise');
      var kin = el.parentNode.children, i = Array.prototype.indexOf.call(kin, el);
      if (kin.length > 2) el.style.transitionDelay = (i % 4) * 70 + 'ms';
      pics.push(el);
    });
  }
  if ('IntersectionObserver' in window) {
    var po = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('is-in'); po.unobserve(e.target); } });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.05 });
    pics.forEach(function (p) { po.observe(p); });
    window.addEventListener('load', function () { setTimeout(function () {
      pics.forEach(function (p) { var r = p.getBoundingClientRect(); if (r.top < innerHeight && r.bottom > 0) p.classList.add('is-in'); });
    }, 2500); });
  } else {
    pics.forEach(function (p) { p.classList.add('is-in'); });
  }
})();
