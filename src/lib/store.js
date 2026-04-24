// SPDX-License-Identifier: AGPL-3.0-or-later

import { signal } from '@preact/signals';

export const entries = signal([]);
export const selectedEntry = signal(null);
export const query = signal('');
export const savedSearches = signal([]);
export const capabilities = signal(null);
export const loading = signal(false);
export const updating = signal(false);
