// SPDX-License-Identifier: AGPL-3.0-or-later

import * as store from '../lib/store';

export function SavedSearches({ onSearch }) {
  const searches = store.savedSearches.value;
  const current = store.query.value;

  if (!searches || searches.length === 0) return null;

  return (
    <nav class="saved-searches" role="tablist">
      {searches.map((s) => (
        <button
          key={s.filter}
          role="tab"
          aria-current={current === s.filter ? 'true' : undefined}
          class={current === s.filter ? 'contrast' : 'outline secondary'}
          onClick={() => onSearch(s.filter)}
        >
          {s.label}
        </button>
      ))}
    </nav>
  );
}
