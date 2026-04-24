// SPDX-License-Identifier: AGPL-3.0-or-later

const CACHE_NAME = 'elfeed-web-v1';

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

  // Static assets: cache-first
  event.respondWith(
    caches.match(request).then((cached) => cached || fetch(request))
  );
});
