// SPDX-License-Identifier: AGPL-3.0-or-later

import { useCallback } from 'preact/hooks';
import * as api from '../lib/api';
import * as store from '../lib/store';

export function TagActions({ entry, onTagsChanged }) {
  const tags = entry.tags || [];

  const toggleTag = useCallback(async (tag) => {
    const has = tags.includes(tag);
    const add = has ? [] : [tag];
    const remove = has ? [tag] : [];
    const result = await api.updateTags(add, remove, [entry.webid]);
    onTagsChanged(result);
  }, [entry, tags, onTagsChanged]);

  const isUnread = tags.includes('unread');

  return (
    <div class="tag-actions">
      <button
        aria-pressed={isUnread ? 'true' : 'false'}
        class={isUnread ? '' : 'outline'}
        onClick={() => toggleTag('unread')}
      >
        {isUnread ? 'Mark read' : 'Mark unread'}
      </button>
      <button
        aria-pressed={tags.includes('★') ? 'true' : 'false'}
        class={tags.includes('★') ? '' : 'outline'}
        onClick={() => toggleTag('★')}
      >
        ★
      </button>
      <button
        aria-pressed={tags.includes('later') ? 'true' : 'false'}
        class={tags.includes('later') ? '' : 'outline'}
        onClick={() => toggleTag('later')}
      >
        Later
      </button>
    </div>
  );
}
