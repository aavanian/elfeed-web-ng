// SPDX-License-Identifier: AGPL-3.0-or-later

import { useState } from 'preact/hooks';
import * as store from '../lib/store';

export function SearchBar({ onSearch }) {
  const [input, setInput] = useState('');
  const loading = store.loading.value;

  const handleSubmit = (e) => {
    e.preventDefault();
    if (input.trim()) {
      onSearch(input.trim());
    }
  };

  return (
    <form class="search-bar" onSubmit={handleSubmit} role="search">
      <input
        type="search"
        placeholder="Filter: @3-days-old +unread"
        value={input}
        onInput={(e) => setInput(e.target.value)}
        aria-label="Search filter"
      />
      <button type="submit" aria-busy={loading}>
        Search
      </button>
    </form>
  );
}
