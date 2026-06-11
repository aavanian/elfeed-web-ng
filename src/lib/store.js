// SPDX-License-Identifier: AGPL-3.0-or-later

import { signal } from '@preact/signals';

export const entries = signal([]);
export const selectedEntry = signal(null);
export const query = signal('');
export const savedSearches = signal([]);
export const capabilities = signal(null);
export const loading = signal(false);
export const updating = signal(false);
export const error = signal(null);

// Swap an entry in `entries` for an updated copy, matched by webid. Entries are
// identified by webid throughout the UI, so every in-place edit (tagging,
// annotating, swipe-to-read) routes through here.
export function replaceEntry(updated) {
  entries.value = entries.value.map(e =>
    e.webid === updated.webid ? updated : e
  );
}
