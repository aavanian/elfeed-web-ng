// SPDX-License-Identifier: AGPL-3.0-or-later

import * as store from '../lib/store';

export function SearchBar({ onSearch }) {
  const query = store.query.value;
  const loading = store.loading.value;

  const handleSubmit = (e) => {
    e.preventDefault();
    if (query.trim()) {
      onSearch(query.trim());
    }
  };

  return (
    <form class="search-bar" onSubmit={handleSubmit} role="search">
      <input
        type="search"
        placeholder="Filter: @3-days-old +unread"
        value={query}
        onInput={(e) => { store.query.value = e.target.value; }}
        aria-label="Search filter"
      />
      <button type="submit" aria-busy={loading}>
        Search
      </button>
    </form>
  );
}
