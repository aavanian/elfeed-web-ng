// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'preact/hooks';

const build = __BUILD_INFO__;

// The stylesheet carries its own copy of the build id. Reading it back tells us
// which CSS the browser actually loaded, which is the one thing the bundle
// cannot know about itself: caches can serve a stale stylesheet alongside a
// fresh script, and the mismatch is otherwise invisible.
function cssBuildId() {
  const raw = getComputedStyle(document.documentElement)
    .getPropertyValue('--build-id')
    .trim()
    .replace(/^["']|["']$/g, '');
  return raw || 'missing';
}

// Name an element the way it appears in the source, so a reading of the panel
// points straight at a selector.
function describe(el) {
  const cls = (el.className || '').toString().trim().split(/\s+/).filter(Boolean);
  return el.tagName.toLowerCase() + (cls.length ? '.' + cls.join('.') : '');
}

// Anything reaching past the viewport's right edge, widest first. A page that
// scrolls sideways on a phone shows every element shifted, which says nothing
// about which one is doing the pushing — this names it. An element whose own
// descendant reaches just as far is only inheriting the overflow, so drop it
// and report the innermost element at each width: that is the one to fix.
function overflowing() {
  const limit = document.documentElement.clientWidth;
  const over = [...document.querySelectorAll('body *')]
    .map((el) => ({ el, right: el.getBoundingClientRect().right }))
    .filter(({ el, right }) => right > limit + 1 && !el.closest('.build-info'));
  const innermost = over.filter(({ el, right }) =>
    !over.some((other) => other.el !== el && el.contains(other.el) && other.right > right - 1));
  return innermost
    .sort((a, b) => b.right - a.right)
    .slice(0, 6)
    .map(({ el, right }) => `${describe(el)} → ${Math.round(right)}`);
}

export function BuildInfo({ onClose }) {
  const [css] = useState(cssBuildId);
  const [layout] = useState(() => ({
    viewport: document.documentElement.clientWidth,
    document: document.documentElement.scrollWidth,
    offenders: overflowing(),
  }));

  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const stale = css !== build.buildId;
  const sw = navigator.serviceWorker?.controller ? 'controlling' : 'none';

  return (
    <div class="build-info" role="dialog" aria-label="Build info" onClick={onClose}>
      <dl>
        <dt>version</dt>
        <dd>{build.describe}</dd>
        <dt>branch</dt>
        <dd>{build.branch}@{build.commit}</dd>
        <dt>built</dt>
        <dd>{new Date(build.date).toLocaleString()}</dd>
        <dt>js</dt>
        <dd>{build.buildId}</dd>
        <dt>css</dt>
        <dd class={stale ? 'stale' : ''}>{css}{stale ? ' (stale)' : ''}</dd>
        <dt>sw</dt>
        <dd>{sw}</dd>
        <dt>width</dt>
        <dd class={layout.document > layout.viewport ? 'stale' : ''}>
          {layout.viewport} / {layout.document}
        </dd>
        {layout.offenders.length > 0 && (
          <>
            <dt>over</dt>
            <dd>{layout.offenders.map((o) => <div key={o}>{o}</div>)}</dd>
          </>
        )}
      </dl>
    </div>
  );
}
