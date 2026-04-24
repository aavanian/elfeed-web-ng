// SPDX-License-Identifier: AGPL-3.0-or-later

import { useState, useRef, useCallback, useEffect } from 'preact/hooks';
import * as store from '../lib/store';
import * as api from '../lib/api';

function formatDate(ms) {
  const d = new Date(ms);
  return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

const SWIPE_THRESHOLD = 80;

function SwipeableEntryItem({ entry, isSelected, onSelect }) {
  const [swipeX, setSwipeX] = useState(0);
  const [snapping, setSnapping] = useState(false);
  const touch = useRef({ startX: 0, startY: 0, active: false, done: false, currentX: 0 });
  const liRef = useRef(null);

  const isUnread = entry.tags?.includes('unread');

  const handleTouchStart = (e) => {
    const t = e.touches[0];
    touch.current = { startX: t.clientX, startY: t.clientY, active: false, done: false, currentX: 0 };
    setSnapping(false);
  };

  const onTouchMove = useCallback((e) => {
    const t = e.touches[0];
    const dx = t.clientX - touch.current.startX;
    const dy = t.clientY - touch.current.startY;

    if (!touch.current.active) {
      if (Math.abs(dy) >= Math.abs(dx)) return; // vertical — let scroll happen
      if (Math.abs(dx) < 8) return; // not enough movement yet
      touch.current.active = true;
    }

    if (dx >= 0) return; // only left swipe
    e.preventDefault();
    touch.current.currentX = dx;
    setSwipeX(dx);
  }, []);

  useEffect(() => {
    const el = liRef.current;
    if (!el) return;
    el.addEventListener('touchmove', onTouchMove, { passive: false });
    return () => el.removeEventListener('touchmove', onTouchMove);
  }, [onTouchMove]);

  const handleTouchEnd = async (e) => {
    if (!touch.current.active) return;
    // changedTouches gives the authoritative final position; touchmove may
    // not have caught up on fast swipes, making currentX unreliable.
    const t = e.changedTouches[0];
    const dx = t.clientX - touch.current.startX;

    // Snap back immediately so the tray doesn't stay lit while the API call runs.
    setSnapping(true);
    setSwipeX(0);

    if (dx < -SWIPE_THRESHOLD) {
      touch.current.done = true;
      const tags = entry.tags ?? [];
      const add = isUnread ? [] : ['unread'];
      const remove = isUnread ? ['unread'] : [];
      try {
        await api.updateTags(add, remove, [entry.webid]);
        const newTags = isUnread
          ? tags.filter(t => t !== 'unread')
          : [...tags, 'unread'];
        const updatedEntry = { ...entry, tags: newTags };
        store.entries.value = store.entries.value.map(e =>
          e.webid === updatedEntry.webid ? updatedEntry : e
        );
      } catch (_) {
        // Flash the tray red briefly so the user sees the action failed.
        setSnapping(false);
        setSwipeX(-(SWIPE_THRESHOLD + 20));
        await new Promise(r => setTimeout(r, 800));
        setSnapping(true);
        setSwipeX(0);
      }
    }
  };

  const handleClick = () => {
    if (touch.current.done) {
      touch.current.done = false;
      return;
    }
    onSelect(entry);
  };

  const swipeLabel = isUnread ? '✓ Mark read' : '↩ Mark unread';

  return (
    <li
      ref={liRef}
      class={`entry-item ${isUnread ? 'unread' : ''}`}
      aria-selected={isSelected ? 'true' : undefined}
      onClick={handleClick}
      onTouchStart={handleTouchStart}
      onTouchEnd={handleTouchEnd}
    >
      <div class="swipe-bg" aria-hidden="true">{swipeLabel}</div>
      <div
        class="entry-item-inner"
        style={`transform: translateX(${swipeX}px); transition: ${snapping ? 'transform 0.2s ease' : 'none'};`}
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
      </div>
    </li>
  );
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
      <div class="entry-list-header">
        <small class="secondary">{entryList.length} entries</small>
        <button class="outline secondary mark-all-read"
                onClick={handleMarkAllRead}>
          Mark all read
        </button>
      </div>
      {entryList.length === 0 ? (
        <p class="no-results">No results.</p>
      ) : (
        <ul class="entry-list">
          {entryList.map((entry) => (
            <SwipeableEntryItem
              key={entry.webid}
              entry={entry}
              isSelected={selected?.webid === entry.webid}
              onSelect={onSelect}
            />
          ))}
        </ul>
      )}
    </div>
  );
}
