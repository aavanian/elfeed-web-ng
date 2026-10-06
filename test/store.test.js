// SPDX-License-Identifier: AGPL-3.0-or-later

import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as store from '../src/lib/store.js';

test('replaceEntry swaps the entry with the same webid', () => {
  const a = { webid: 'a', tags: ['unread'] };
  const b = { webid: 'b', tags: [] };
  store.entries.value = [a, b];

  store.replaceEntry({ webid: 'a', tags: [] });

  assert.deepEqual(store.entries.value, [{ webid: 'a', tags: [] }, b]);
  assert.equal(store.entries.value[1], b);
});

test('replaceEntry leaves the list alone for an unknown webid', () => {
  const a = { webid: 'a', tags: [] };
  store.entries.value = [a];

  store.replaceEntry({ webid: 'z', tags: ['unread'] });

  assert.deepEqual(store.entries.value, [a]);
});

test('replaceEntry refreshes the open entry it replaces', () => {
  const a = { webid: 'a', tags: ['unread'] };
  store.entries.value = [a];
  store.selectedEntry.value = a;

  store.replaceEntry({ webid: 'a', tags: [] });

  assert.deepEqual(store.selectedEntry.value, { webid: 'a', tags: [] });
});

test('replaceEntry leaves another open entry alone', () => {
  const a = { webid: 'a', tags: [] };
  const b = { webid: 'b', tags: [] };
  store.entries.value = [a, b];
  store.selectedEntry.value = b;

  store.replaceEntry({ webid: 'a', tags: ['later'] });

  assert.equal(store.selectedEntry.value, b);
});
