// SPDX-License-Identifier: AGPL-3.0-or-later

import { useCallback } from 'preact/hooks';
import * as api from '../lib/api';
import * as store from '../lib/store';
import { TagActions } from './TagActions';
import { AnnotationEditor } from './AnnotationEditor';

function formatDate(ms) {
  return new Date(ms).toLocaleDateString(undefined, {
    year: 'numeric', month: 'short', day: 'numeric',
  });
}

export function EntryContent({ entry, onBack, onSearch }) {
  const contentUrl = entry.content ? api.getContentUrl(entry.content) : null;

  const handleTagsChanged = useCallback(async () => {
    await onSearch(store.query.value);
  }, [onSearch]);

  return (
    <article>
      <button class="back-button outline secondary" onClick={onBack}>
        &larr; Back
      </button>

      <div class="content-header">
        <h2>
          <a href={entry.link} target="_blank" rel="noopener noreferrer">
            {entry.title}
          </a>
        </h2>
        <div class="content-meta">
          <span>{entry.feed?.title}</span>
          {' — '}
          <span>{formatDate(entry.date)}</span>
        </div>
      </div>

      <TagActions entry={entry} onTagsChanged={handleTagsChanged} />

      {contentUrl ? (
        <iframe
          class="content-frame"
          src={contentUrl}
          sandbox=""
          title="Entry content"
        />
      ) : (
        <p class="secondary">No content available.</p>
      )}

      <AnnotationEditor entry={entry} />
    </article>
  );
}
