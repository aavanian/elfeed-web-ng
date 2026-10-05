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
