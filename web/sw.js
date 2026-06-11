// SPDX-License-Identifier: AGPL-3.0-or-later

// The build id below is stamped at build time (see vite.config.js) so
// CACHE_NAME changes on every build, letting the activate handler evict
// stale shells.
const CACHE_NAME = 'elfeed-web-mq9e1pfr';

const STATIC_ASSETS = [
  '/elfeed/',
  '/elfeed/manifest.json',
];

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

  // API calls: network-first
  const p = url.pathname;
  if (url.pathname.startsWith('/elfeed/') &&
      (p.includes('/search') ||
       p.includes('/tags') ||
       p === '/elfeed/feed-update' ||
       p === '/elfeed/feed-update-done' ||
       p.includes('/api') ||
       p.includes('/annotation') ||
       p.includes('/saved-searches') ||
       p.includes('/things') ||
       p.includes('/content') ||
       p.includes('/mark-all-read'))) {
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
