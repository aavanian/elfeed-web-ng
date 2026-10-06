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
  const context = vm.createContext({ self: { addEventListener() {} }, URL });
  vm.runInContext(source, context);
  return context;
}

const { isStaticAsset } = loadServiceWorker();

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
