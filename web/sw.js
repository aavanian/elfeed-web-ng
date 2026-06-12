// SPDX-License-Identifier: AGPL-3.0-or-later

// The build id below is stamped at build time (see vite.config.js) so
// CACHE_NAME changes on every build, letting the activate handler evict
// stale shells.
const CACHE_NAME = 'elfeed-web-mqaevno4';

const STATIC_ASSETS = [
  '/elfeed/',
  '/elfeed/manifest.json',
];

// The cacheable surface is the build output, which lives at a few fixed
// paths. Anything else under /elfeed/ is an API endpoint, served
// network-first and never cached. Allowlisting the static paths (rather than
// enumerating the API ones) keeps this from drifting as endpoints are added.
function isStaticAsset(p) {
  return (
    p === '/elfeed/' ||
    p === '/elfeed/index.html' ||
    p === '/elfeed/manifest.json' ||
    p === '/elfeed/sw.js' ||
    p.startsWith('/elfeed/assets/') ||
    p.startsWith('/elfeed/icons/')
  );
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(STATIC_ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // API calls: network-first, never cached.
  const p = url.pathname;
  if (p.startsWith('/elfeed/') && !isStaticAsset(p)) {
    event.respondWith(
      fetch(request).catch(() => caches.match(request))
    );
    return;
  }

  // App shell (navigations + static assets): network-first so online devices
  // always pull the fresh build; fall back to cache when offline.
  event.respondWith(
    fetch(request)
      .then((response) => {
        if (response.ok && request.method === 'GET') {
          const copy = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
        }
        return response;
      })
      .catch(() => caches.match(request))
  );
});
