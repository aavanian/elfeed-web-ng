// SPDX-License-Identifier: AGPL-3.0-or-later

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

// sw.js is a classic worker script, not a module: evaluate it in a context
// with just enough of the worker global to register its listeners, then
// read its top-level functions off that context.
function loadServiceWorker() {
  const source = readFileSync(new URL('../src/public/sw.js', import.meta.url), 'utf8');
  const listeners = {};
  const context = vm.createContext({
    self: { addEventListener(type, fn) { listeners[type] = fn; } },
    URL,
  });
  vm.runInContext(source, context);
  context.listeners = listeners;
  return context;
}

const { isStaticAsset, listeners } = loadServiceWorker();

// Dispatch a fetch event for PATH and report whether the worker answered it.
function workerAnswers(path, method = 'GET') {
  let answered = false;
  listeners.fetch({
    request: { url: `http://127.0.0.1:8082${path}`, method },
    respondWith() { answered = true; },
  });
  return answered;
}

test('the build output is a static asset', () => {
  for (const p of [
    '/elfeed/',
    '/elfeed/index.html',
    '/elfeed/manifest.json',
    '/elfeed/sw.js',
    '/elfeed/assets/index.js',
    '/elfeed/assets/index.css',
    '/elfeed/icons/favicon_dark.svg',
  ]) {
    assert.equal(isStaticAsset(p), true, p);
  }
});

test('API endpoints are never static assets', () => {
  for (const p of [
    '/elfeed/api',
    '/elfeed/search',
    '/elfeed/tags',
    '/elfeed/things/x',
    '/elfeed/content/abc',
    '/elfeed/feed-update',
    '/elfeed/feed-update-done',
    '/elfeed/mark-all-read',
    '/elfeed/saved-searches',
    '/elfeed/annotation/x',
  ]) {
    assert.equal(isStaticAsset(p), false, p);
  }
});

test('API requests go straight to the network, untouched', () => {
  for (const [path, method] of [
    ['/elfeed/search', 'GET'],
    ['/elfeed/tags', 'PUT'],
    ['/elfeed/feed-update-done', 'GET'],
  ]) {
    assert.equal(workerAnswers(path, method), false, path);
  }
});
