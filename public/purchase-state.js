(() => {
  const KEY = 'gc:demo:purchase:v1';

  function read() {
    try {
      const value = JSON.parse(localStorage.getItem(KEY) || 'null');
      return value && value.completed ? value : null;
    } catch {
      return null;
    }
  }

  function write(purchase) {
    const value = {
      completed: true,
      completedAt: new Date().toISOString(),
      receipt: 'GC-' + Date.now().toString(36).toUpperCase(),
      ...purchase,
    };
    try { localStorage.setItem(KEY, JSON.stringify(value)); } catch {}
    render();
    try { window.dispatchEvent(new CustomEvent('guidecursor:purchase', { detail: value })); } catch {}
    return value;
  }

  function clear() {
    try { localStorage.removeItem(KEY); } catch {}
    render();
  }

  function render() {
    const purchase = read();
    document.querySelectorAll('[data-purchase-download]').forEach((el) => {
      el.hidden = !purchase;
      el.setAttribute('aria-hidden', purchase ? 'false' : 'true');
    });
    document.documentElement.classList.toggle('gc-has-purchase', !!purchase);
  }

  function fakeDownload(platform = 'mac') {
    const purchase = read();
    if (!purchase) return false;
    const isWindows = platform === 'windows';
    const filename = isWindows ? 'GuideCursor-Windows11-Demo.exe' : 'GuideCursor-macOS-Demo.dmg';
    const body = [
      'GuideCursor Demo Installer',
      '',
      'This is a simulated download created by the GuideCursor DBIS MVP.',
      'It is not executable software and installs nothing.',
      '',
      'Platform: ' + (isWindows ? 'Windows 11' : 'macOS'),
      'Plan: ' + (purchase.plan || 'Personal'),
      'Receipt: ' + (purchase.receipt || 'Demo'),
      'Generated: ' + new Date().toISOString(),
    ].join('\n');
    const blob = new Blob([body], { type: 'application/octet-stream' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    return true;
  }

  window.GuideCursorPurchase = {
    key: KEY,
    read,
    complete: write,
    clear,
    hasPurchase: () => !!read(),
    fakeDownload,
    render,
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', render, { once: true });
  } else {
    render();
  }
  window.addEventListener('storage', (event) => {
    if (event.key === KEY) render();
  });
})();
