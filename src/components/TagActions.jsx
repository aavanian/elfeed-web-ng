// SPDX-License-Identifier: AGPL-3.0-or-later

import { useCallback, useState } from 'preact/hooks';
import * as api from '../lib/api';

export function TagActions({ entry, onTagsChanged }) {
  const tags = entry.tags || [];
  const [pending, setPending] = useState(null);

  const toggleTag = useCallback(async (tag) => {
    if (pending !== null) return;
    setPending(tag);
    try {
      const has = tags.includes(tag);
      const add = has ? [] : [tag];
      const remove = has ? [tag] : [];
      await api.updateTags(add, remove, [entry.webid]);
      const newTags = has ? tags.filter(t => t !== tag) : [...tags, tag];
      onTagsChanged({ ...entry, tags: newTags });
    } finally {
      setPending(null);
    }
  }, [entry, tags, onTagsChanged, pending]);

  const isUnread = tags.includes('unread');
  const disabled = pending !== null;

  return (
    <div class="tag-actions">
      <button
        aria-pressed={isUnread ? 'true' : 'false'}
        class={isUnread ? '' : 'outline'}
        disabled={disabled}
        aria-busy={pending === 'unread'}
        onClick={() => toggleTag('unread')}
      >
        {isUnread ? 'Mark read' : 'Mark unread'}
      </button>
      <button
        aria-pressed={tags.includes('★') ? 'true' : 'false'}
        class={tags.includes('★') ? '' : 'outline'}
        aria-label="Favourite"
        disabled={disabled}
        aria-busy={pending === '★'}
        onClick={() => toggleTag('★')}
      >
        ★
      </button>
      <button
        aria-pressed={tags.includes('later') ? 'true' : 'false'}
        class={tags.includes('later') ? '' : 'outline'}
        disabled={disabled}
        aria-busy={pending === 'later'}
        onClick={() => toggleTag('later')}
      >
        Later
      </button>
    </div>
  );
}
