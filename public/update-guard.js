(() => {
  window.__gcUpdateGuardV2 = true;

  const BUILD_META = 'meta[name="guidecursor-build"]';
  const ACK_BUILD = 'gc:update:v2:ack-build';
  const ACK_COMMIT = 'gc:update:v2:ack-commit';
  const ACK_SEQUENCE = 'gc:update:v2:ack-sequence';
  const PENDING = 'gc:update:v2:pending';
  const LAST_OBSERVED = 'gc:update:v2:last-observed';
  const INITIALIZED = 'gc:update:v2:initialized';
  const CHECK_MS = 3000;

  let modal, button, countEl, titleEl, bodyEl, oldBuildEl, newBuildEl, noteEl;
  let latest = null;
  let checking = false;
  let visible = false;
  let timer = null;
  let channel = null;
  let displayedBuild = '';
  let displayedCount = 0;
  let lastBroadcastBuild = '';

  const loadedBuild = () => (document.querySelector(BUILD_META)?.content || '').trim();
  const safeParse = (value, fallback) => { try { return JSON.parse(value); } catch { return fallback; } };
  const short = (value, n = 8) => (value || '').slice(0, n) || 'unknown';

  function readPending() {
    const items = safeParse(localStorage.getItem(PENDING) || '[]', []);
    return Array.isArray(items) ? items : [];
  }

  function writePending(items) {
    try { localStorage.setItem(PENDING, JSON.stringify(items.slice(-30))); } catch {}
  }

  function rememberBuild(data) {
    if (!data?.build) return;
    const pending = readPending();
    if (!pending.some(item => item.build === data.build)) {
      pending.push({ build: data.build, commit: data.commit || '', generatedAt: data.generatedAt || new Date().toISOString() });
      writePending(pending);
    }
    try { localStorage.setItem(LAST_OBSERVED, data.build); } catch {}
  }

  function exactMissedCount(data) {
    const ackSequence = Number(localStorage.getItem(ACK_SEQUENCE) || '');
    const currentSequence = Number(data?.sequence);
    if (Number.isFinite(ackSequence) && ackSequence > 0 && Number.isFinite(currentSequence) && currentSequence > 0) {
      return Math.max(0, currentSequence - ackSequence);
    }

    const ackCommit = localStorage.getItem(ACK_COMMIT) || '';
    const history = Array.isArray(data?.history) ? data.history : [];
    if (ackCommit && history.length) {
      const idx = history.findIndex(item => item === ackCommit || item.startsWith(ackCommit) || ackCommit.startsWith(item));
      if (idx >= 0) return idx;
    }

    const ackBuild = localStorage.getItem(ACK_BUILD) || '';
    const pending = readPending().filter(item => item.build && item.build !== ackBuild);
    return Math.max(ackBuild && data?.build !== ackBuild ? 1 : 0, new Set(pending.map(item => item.build)).size);
  }

  function stableMissedCount(data) {
    const computed = Math.max(1, exactMissedCount(data));
    if (displayedBuild !== data.build) {
      displayedBuild = data.build;
      displayedCount = computed;
      return displayedCount;
    }
    displayedCount = Math.max(displayedCount || 1, computed);
    return displayedCount;
  }

  function ensureModal() {
    if (modal) return;
    modal = document.createElement('div');
    modal.className = 'gc-update-v2';
    modal.id = 'gc-update-v2';
    modal.hidden = true;
    modal.setAttribute('role', 'alertdialog');
    modal.setAttribute('aria-modal', 'true');
    modal.setAttribute('aria-labelledby', 'gc-update-title');
    modal.setAttribute('aria-describedby', 'gc-update-body');
    modal.innerHTML = `
      <div class="gc-update-card">
        <div class="gc-update-top">
          <span class="gc-update-badge"><i></i> New deployment detected</span>
          <span class="gc-update-count"><strong id="gc-update-count">1</strong><span id="gc-update-count-label">update missed</span></span>
        </div>
        <div class="gc-update-copy">
          <h2 id="gc-update-title">GuideCursor just got <span>newer.</span></h2>
          <p id="gc-update-body">A newer production build is available. Refresh through this prompt so you know you are seeing the latest version.</p>
        </div>
        <div class="gc-update-timeline">
          <div class="gc-update-timeline-head"><span>Version change</span><span id="gc-update-status">Ready to refresh</span></div>
          <div class="gc-update-track"><i></i></div>
          <div class="gc-update-builds"><b id="gc-update-old">current</b><i></i><b id="gc-update-new">latest</b></div>
        </div>
        <button class="gc-update-refresh" id="gc-update-refresh" type="button">
          <span class="gc-update-icon">↻</span><span>Hard refresh to latest version</span>
        </button>
        <div class="gc-update-note"><i></i><span id="gc-update-note">The prompt stays until you explicitly load the update.</span></div>
      </div>`;
    document.body.appendChild(modal);
    button = modal.querySelector('#gc-update-refresh');
    countEl = modal.querySelector('#gc-update-count');
    titleEl = modal.querySelector('#gc-update-title');
    bodyEl = modal.querySelector('#gc-update-body');
    oldBuildEl = modal.querySelector('#gc-update-old');
    newBuildEl = modal.querySelector('#gc-update-new');
    noteEl = modal.querySelector('#gc-update-note');

    button.addEventListener('click', acknowledgeAndReload);
    modal.addEventListener('click', (event) => { if (event.target === modal) button.focus(); });
  }

  function animateCount(to) {
    if (!countEl) return;
    const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduce || to <= 1) { countEl.textContent = String(to); return; }
    const start = performance.now(), duration = 520;
    const tick = (now) => {
      const p = Math.min(1, (now - start) / duration);
      countEl.textContent = String(Math.max(1, Math.round(to * (1 - Math.pow(1 - p, 3)))));
      if (p < 1) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }

  function showUpdate(data, { broadcast = false } = {}) {
    ensureModal();
    latest = data;
    rememberBuild(data);
    const previousBuild = displayedBuild;
    const previousCount = displayedCount;
    const count = stableMissedCount(data);
    window.GuideCursorTitle?.setSystem(count > 1 ? 'Update available — '+count+' missed · GuideCursor' : 'Update available — GuideCursor');
    const label = modal.querySelector('#gc-update-count-label');
    label.textContent = count === 1 ? 'update missed' : 'updates missed';
    const countChanged = !visible || previousBuild !== data.build || previousCount !== count;
    if (countChanged) animateCount(count);
    else countEl.textContent = String(count);

    const onLatestPage = loadedBuild() === data.build;
    titleEl.innerHTML = count > 1
      ? `You missed <span>${count} updates.</span>`
      : `GuideCursor just got <span>newer.</span>`;
    bodyEl.textContent = onLatestPage
      ? 'You refreshed the page, but this update has not been acknowledged yet. Use the button below once so the browser clears stale caches and records the latest build.'
      : 'A newer production build is live while this tab is still running an older version. The prompt will remain even if you do a normal refresh.';
    oldBuildEl.textContent = short(localStorage.getItem(ACK_COMMIT) || loadedBuild());
    newBuildEl.textContent = short(data.commit || data.build);
    noteEl.textContent = count > 1
      ? `${count} production updates detected since your last acknowledged build.`
      : 'The prompt stays until you explicitly load the update.';

    modal.hidden = false;
    document.body.classList.add('gc-update-v2-open');
    visible = true;
    requestAnimationFrame(() => button.focus());

    if (broadcast && lastBroadcastBuild !== data.build) {
      lastBroadcastBuild = data.build;
      try { channel?.postMessage({ type: 'update', data }); } catch {}
    }
  }

  function hideUpdate() {
    if (!modal) return;
    modal.hidden = true;
    document.body.classList.remove('gc-update-v2-open');
    visible = false;
    window.GuideCursorTitle?.clearSystem();
  }

  async function fetchLatest() {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);
    try {
      const url = '/version.json?gc_update_check=' + Date.now() + '_' + Math.random().toString(36).slice(2);
      const response = await fetch(url, {
        cache: 'no-store',
        credentials: 'same-origin',
        headers: {
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0'
        },
        signal: controller.signal
      });
      if (!response.ok) return null;
      return await response.json();
    } catch {
      return null;
    } finally {
      clearTimeout(timeout);
    }
  }

  async function checkNow({ first = false } = {}) {
    if (checking) return;
    checking = true;
    try {
      const data = await fetchLatest();
      if (!data?.build) return;
      latest = data;

      const current = loadedBuild();
      const ackBuild = localStorage.getItem(ACK_BUILD) || '';
      const initialized = localStorage.getItem(INITIALIZED) === '1';

      if (!initialized) {
        try { localStorage.setItem(INITIALIZED, '1'); } catch {}
        if (!ackBuild && current && current === data.build) {
          const navigationType = performance.getEntriesByType?.('navigation')?.[0]?.type || '';
          if (navigationType === 'reload') {
            rememberBuild(data);
            showUpdate(data, { broadcast: true });
            return;
          }
          try {
            localStorage.setItem(ACK_BUILD, current);
            if (data.commit) localStorage.setItem(ACK_COMMIT, data.commit);
            if (Number.isFinite(Number(data.sequence))) localStorage.setItem(ACK_SEQUENCE, String(data.sequence));
            localStorage.setItem(LAST_OBSERVED, current);
          } catch {}
          return;
        }
      }

      const previousObserved = localStorage.getItem(LAST_OBSERVED) || '';
      if (previousObserved !== data.build) rememberBuild(data);

      const effectiveAck = localStorage.getItem(ACK_BUILD) || current;
      if (data.build !== effectiveAck) {
        showUpdate(data);
      } else if (visible) {
        hideUpdate();
      }
    } finally {
      checking = false;
    }
  }

  async function acknowledgeAndReload() {
    if (!latest?.build) {
      latest = await fetchLatest();
      if (!latest?.build) return;
    }

    button.disabled = true;
    button.classList.add('is-loading');
    button.querySelector('span:last-child').textContent = 'Loading latest build…';

    try {
      localStorage.setItem(ACK_BUILD, latest.build);
      if (latest.commit) localStorage.setItem(ACK_COMMIT, latest.commit);
      if (Number.isFinite(Number(latest.sequence))) localStorage.setItem(ACK_SEQUENCE, String(latest.sequence));
      localStorage.setItem(LAST_OBSERVED, latest.build);
      localStorage.setItem(PENDING, '[]');
      localStorage.setItem(INITIALIZED, '1');
    } catch {}

    try {
      if ('caches' in window) {
        const keys = await caches.keys();
        await Promise.all(keys.map(key => caches.delete(key)));
      }
    } catch {}

    try { channel?.postMessage({ type: 'ack', build: latest.build, commit: latest.commit || '', sequence: latest.sequence ?? null }); } catch {}

    const url = new URL(location.href);
    url.searchParams.set('__gc_build', latest.build);
    url.searchParams.set('__gc_ack', Date.now().toString());
    location.replace(url.toString());
  }

  function init() {
    ensureModal();

    try {
      channel = new BroadcastChannel('guidecursor-update-v2');
      channel.addEventListener('message', (event) => {
        if (event.data?.type === 'update' && event.data.data?.build) {
          rememberBuild(event.data.data);
          const ack = localStorage.getItem(ACK_BUILD) || loadedBuild();
          if (event.data.data.build !== ack) showUpdate(event.data.data, { broadcast: false });
        }
        if (event.data?.type === 'ack') {
          try {
            localStorage.setItem(ACK_BUILD, event.data.build || '');
            if (event.data.commit) localStorage.setItem(ACK_COMMIT, event.data.commit);
            if (Number.isFinite(Number(event.data.sequence))) localStorage.setItem(ACK_SEQUENCE, String(event.data.sequence));
            localStorage.setItem(PENDING, '[]');
          } catch {}
          if (loadedBuild() === event.data.build) hideUpdate();
        }
      });
    } catch {}

    document.addEventListener('keydown', (event) => {
      if (!visible) return;
      if (event.key === 'Escape') {
        event.preventDefault();
        event.stopImmediatePropagation();
      }
      if (event.key === 'Tab') {
        event.preventDefault();
        button?.focus();
      }
    }, true);

    addEventListener('focus', () => checkNow());
    addEventListener('online', () => checkNow());
    addEventListener('pageshow', () => checkNow());
    document.addEventListener('visibilitychange', () => { if (!document.hidden) checkNow(); });
    addEventListener('storage', (event) => {
      if ([ACK_BUILD, PENDING, LAST_OBSERVED].includes(event.key)) checkNow();
    });

    checkNow({ first: true });
    timer = setInterval(() => checkNow(), CHECK_MS);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init, { once: true });
  else init();
})();