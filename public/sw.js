/* AutoTender service worker — sadə və təhlükəsiz:
   - Supabase və digər API sorğularına TOXUNMUR (həmişə şəbəkədən).
   - Səhifə naviqasiyası: əvvəl şəbəkə, internet yoxdursa köhnə nüsxə.
   - Hash-li statik fayllar (/assets/...): əvvəl keş (dəyişməz fayllardır).
   Yeni versiya yerləşdirəndə VERSION-u dəyişmək lazım deyil: naviqasiya həmişə şəbəkədən yenilənir. */
const VERSION = 'v2';
const SHELL = 'at-shell-' + VERSION;
const ASSETS = 'at-assets-' + VERSION;

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(SHELL).then((c) => c.addAll(['/', '/icon-192.png'])).catch(() => undefined));
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== SHELL && k !== ASSETS).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // Supabase, Telegram və s. — toxunmuruq

  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(SHELL).then((c) => c.put('/', copy)).catch(() => undefined);
          return res;
        })
        .catch(() => caches.match('/').then((r) => r || Response.error()))
    );
    return;
  }

  if (url.pathname.startsWith('/assets/')) {
    event.respondWith(
      caches.match(req).then(
        (hit) =>
          hit ||
          fetch(req).then((res) => {
            if (res.ok) {
              const copy = res.clone();
              caches.open(ASSETS).then((c) => c.put(req, copy)).catch(() => undefined);
            }
            return res;
          })
      )
    );
  }
});
