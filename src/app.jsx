// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useCallback } from 'preact/hooks';
import * as api from './lib/api';
import * as store from './lib/store';
import { SavedSearches } from './components/SavedSearches';
import { SearchBar } from './components/SearchBar';
import { EntryList } from './components/EntryList';
import { EntryContent } from './components/EntryContent';

export function App() {
  useEffect(() => {
    (async () => {
      const caps = await api.init();
      store.capabilities.value = caps;
      const searches = await api.getSavedSearches();
      store.savedSearches.value = searches;

      if (searches.length > 0) {
        store.query.value = searches[0].filter;
      } else {
        store.query.value = '@3-days-old';
      }
      await doSearch(store.query.value);
      startPolling();
    })();
  }, []);

  const doSearch = useCallback(async (q) => {
    store.loading.value = true;
    try {
      const results = await api.search(q);
      store.entries.value = results;
    } finally {
      store.loading.value = false;
    }
  }, []);

  const startPolling = useCallback(async () => {
    try {
      const time = await api.pollUpdate(null);
      store.pollTime.value = time;
      pollLoop();
    } catch { /* polling not critical */ }
  }, []);

  const pollLoop = useCallback(async () => {
    while (true) {
      try {
        const time = await api.pollUpdate(store.pollTime.value);
        store.pollTime.value = time;
        await doSearch(store.query.value);
      } catch {
        await new Promise(r => setTimeout(r, 5000));
      }
    }
  }, [doSearch]);

  const onSearch = useCallback(async (q) => {
    store.query.value = q;
    store.selectedEntry.value = null;
    await doSearch(q);
  }, [doSearch]);

  const onSelectEntry = useCallback((entry) => {
    store.selectedEntry.value = entry;
  }, []);

  const onBack = useCallback(() => {
    store.selectedEntry.value = null;
  }, []);

  const selected = store.selectedEntry.value;

  return (
    <main class="container-fluid">
      <header>
        <h1>Elfeed</h1>
      </header>

      <div class={`app-layout ${selected ? 'has-selection' : ''}`}>
        <div class="list-pane">
          <SavedSearches onSearch={onSearch} />
          <SearchBar onSearch={onSearch} />
          <EntryList
            onSelect={onSelectEntry}
            onSearch={onSearch}
          />
        </div>

        <div class="content-pane">
          {selected && (
            <EntryContent
              entry={selected}
              onBack={onBack}
              onSearch={onSearch}
            />
          )}
        </div>
      </div>
    </main>
  );
}
