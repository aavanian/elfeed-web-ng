// SPDX-License-Identifier: AGPL-3.0-or-later

import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import * as store from '../src/lib/store.js';
import { runSearch } from '../src/lib/search.js';

const realFetch = globalThis.fetch;
let pending;

// Each search request waits until the test settles it by query.
beforeEach(() => {
  pending = new Map();
  globalThis.fetch = (url) => new Promise((resolve, reject) => {
    const q = new URL(url, 'http://x').searchParams.get('q');
    pending.set(q, {
      ok: (entries) => resolve({ ok: true, status: 200, json: async () => entries }),
      fail: () => reject(new TypeError('Failed to fetch')),
    });
  });
  store.entries.value = [];
  store.loading.value = false;
  store.error.value = null;
});
afterEach(() => { globalThis.fetch = realFetch; });

const tick = () => new Promise((r) => setTimeout(r, 0));

test('the latest search wins even when it finishes first', async () => {
  const first = runSearch('old');
  const second = runSearch('new');
  pending.get('new').ok([{ webid: 'n' }]);
  assert.equal(await second, true);
  assert.equal(store.loading.value, false);
  pending.get('old').ok([{ webid: 'o' }]);
  assert.equal(await first, false);
  assert.deepEqual(store.entries.value, [{ webid: 'n' }]);
});

test('loading lasts until the latest search settles', async () => {
  const first = runSearch('old');
  const second = runSearch('new');
  pending.get('old').ok([{ webid: 'o' }]);
  await first;
  assert.equal(store.loading.value, true);
  assert.deepEqual(store.entries.value, []);
  pending.get('new').ok([{ webid: 'n' }]);
  await second;
  assert.equal(store.loading.value, false);
  assert.deepEqual(store.entries.value, [{ webid: 'n' }]);
});

test('a failed search reports an error instead of rejecting', async () => {
  const run = runSearch('q');
  await tick();
  pending.get('q').fail();
  assert.equal(await run, false);
  assert.match(store.error.value, /search failed/i);
  assert.equal(store.loading.value, false);
});

test('a successful search clears a previous error', async () => {
  store.error.value = 'Search failed.';
  const run = runSearch('q');
  pending.get('q').ok([]);
  await run;
  assert.equal(store.error.value, null);
});

test('a stale failure does not report an error', async () => {
  const first = runSearch('old');
  const second = runSearch('new');
  pending.get('new').ok([]);
  await second;
  pending.get('old').fail();
  await first;
  assert.equal(store.error.value, null);
});
