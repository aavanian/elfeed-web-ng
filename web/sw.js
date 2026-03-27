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
  if (url.pathname.startsWith('/elfeed/') &&
      (url.pathname.includes('/search') ||
       url.pathname.includes('/tags') ||
       url.pathname.includes('/update') ||
       url.pathname.includes('/api') ||
       url.pathname.includes('/annotation') ||
       url.pathname.includes('/saved-searches') ||
       url.pathname.includes('/things') ||
       url.pathname.includes('/content') ||
       url.pathname.includes('/mark-all-read'))) {
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
