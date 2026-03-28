// SPDX-License-Identifier: AGPL-3.0-or-later

import * as store from '../lib/store';
import * as api from '../lib/api';

function formatDate(ms) {
  const d = new Date(ms);
  return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

export function EntryList({ onSelect, onSearch }) {
  const entryList = store.entries.value;
  const selected = store.selectedEntry.value;
  const loading = store.loading.value;

  if (loading && entryList.length === 0) {
    return <div class="loading-bar" />;
  }

  const handleMarkAllRead = async () => {
    await api.markAllRead();
    onSearch(store.query.value);
  };

  return (
    <div>
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
        <small class="secondary">{entryList.length} entries</small>
        <button class="outline secondary" style="font-size: 0.7rem; padding: 0.15rem 0.5rem; margin: 0;"
                onClick={handleMarkAllRead}>
          Mark all read
        </button>
      </div>
      {entryList.length === 0 ? (
        <p class="no-results">No results.</p>
      ) : (
        <ul class="entry-list">
          {entryList.map((entry) => {
            const isUnread = entry.tags?.includes('unread');
            const isSelected = selected?.webid === entry.webid;
            return (
              <li
                key={entry.webid}
                class={`entry-item ${isUnread ? 'unread' : ''}`}
                aria-selected={isSelected ? 'true' : undefined}
                onClick={() => onSelect(entry)}
              >
                <div class="entry-meta">
                  <span>{entry.feed?.title || 'Unknown'}</span>
                  <span>{formatDate(entry.date)}</span>
                </div>
                <div class="entry-title">{entry.title}</div>
                <div class="entry-tags">
                  {(entry.tags || []).map((tag) => (
                    <span key={tag} class="tag-badge">{tag}</span>
                  ))}
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
