// SPDX-License-Identifier: AGPL-3.0-or-later

import { useCallback, useEffect, useState } from "preact/hooks";
import * as api from "../lib/api";
import * as store from "../lib/store";
import { TagActions } from "./TagActions";
import { AnnotationEditor } from "./AnnotationEditor";

const CONTENT_STYLE = `
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    ul, ol { padding-left: 1em; }
  </style>
`;

function rewriteLinks(html) {
  const doc = new DOMParser().parseFromString(html, 'text/html');
  doc.querySelectorAll('a[href]').forEach(a => {
    a.target = '_blank';
    a.rel = 'noopener noreferrer';
  });
  return doc.body.innerHTML;
}

function formatDate(ms) {
  return new Date(ms).toLocaleDateString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

export function EntryContent({ entry, onBack }) {
  const contentUrl = entry.content ? api.getContentUrl(entry.content) : null;
  const [srcdoc, setSrcdoc] = useState(null);

  useEffect(() => {
    if (!contentUrl) {
      setSrcdoc(null);
      return;
    }
    let cancelled = false;
    fetch(contentUrl)
      .then((res) => res.text())
      .then((html) => {
        if (!cancelled) setSrcdoc(CONTENT_STYLE + rewriteLinks(html));
      })
      .catch(() => {
        if (!cancelled) setSrcdoc(CONTENT_STYLE);
      });
    return () => {
      cancelled = true;
    };
  }, [contentUrl]);

  const handleTagsChanged = useCallback((updatedEntry) => {
    store.entries.value = store.entries.value.map(e =>
      e.webid === updatedEntry.webid ? updatedEntry : e
    );
    store.selectedEntry.value = updatedEntry;
  }, []);

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
          {" — "}
          <span>{formatDate(entry.date)}</span>
        </div>
      </div>

      <TagActions entry={entry} onTagsChanged={handleTagsChanged} />

      {contentUrl ? (
        <iframe
          class="content-frame"
          srcdoc={srcdoc ?? ""}
          sandbox="allow-popups"
          title="Entry content"
        />
      ) : (
        <p class="secondary">No content available.</p>
      )}

      <AnnotationEditor entry={entry} />
    </article>
  );
}
