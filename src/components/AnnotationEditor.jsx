// SPDX-License-Identifier: AGPL-3.0-or-later

import { useState, useEffect } from 'preact/hooks';
import * as api from '../lib/api';

export function AnnotationEditor({ entry }) {
  const [text, setText] = useState(entry.annotation || '');
  const [saving, setSaving] = useState(false);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    setText(entry.annotation || '');
    setOpen(!!entry.annotation);
  }, [entry.webid]);

  if (!api.hasFeature('annotations')) return null;

  const save = async () => {
    setSaving(true);
    try {
      await api.setAnnotation(entry.webid, text);
    } finally {
      setSaving(false);
    }
  };

  if (!open) {
    return (
      <button class="outline secondary" style="font-size: 0.75rem; padding: 0.2rem 0.5rem; margin-top: 0.5rem;"
              onClick={() => setOpen(true)}>
        {entry.annotation ? 'Edit annotation' : 'Add annotation'}
      </button>
    );
  }

  return (
    <div class="annotation-editor">
      <textarea
        value={text}
        onInput={(e) => setText(e.target.value)}
        placeholder="Add annotation..."
      />
      <div class="annotation-actions">
        <button onClick={save} aria-busy={saving} disabled={saving}>
          Save
        </button>
        <button class="outline secondary" onClick={() => setOpen(false)}>
          Cancel
        </button>
      </div>
    </div>
  );
}
