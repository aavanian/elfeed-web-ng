// SPDX-License-Identifier: AGPL-3.0-or-later

import * as api from './api.js';
import * as store from './store.js';

// Number of the most recent search. A search applies its results, and ends
// the loading state, only while it is still the most recent one, so a slow
// earlier search cannot overwrite the results of a later one.
let latest = 0;

// Search for QUERY and show its results. Resolves to true when they were
// shown; a failure is reported through `store.error` rather than rejected,
// so callers in event handlers need not catch.
export async function runSearch(query) {
  const id = ++latest;
  store.loading.value = true;
  try {
    const results = await api.search(query);
    if (id !== latest) return false;
    store.entries.value = results;
    store.error.value = null;
    return true;
  } catch {
    if (id === latest) store.error.value = 'Search failed. Is Emacs running?';
    return false;
  } finally {
    if (id === latest) store.loading.value = false;
  }
}
