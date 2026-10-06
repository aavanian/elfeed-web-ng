// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useLayoutEffect, useCallback, useRef, useState } from 'preact/hooks';
import * as api from './lib/api';
import * as store from './lib/store';
import { runSearch } from './lib/search';
import { SavedSearches } from './components/SavedSearches';
import { SearchBar } from './components/SearchBar';
import { EntryList } from './components/EntryList';
import { EntryContent } from './components/EntryContent';
import { BuildInfo } from './components/BuildInfo';

// Window scroll offset of the list at the moment an entry was opened, so we can
// return the reader to where they were when they go back.
let savedScrollY = 0;

export function App() {
  // Set when a back navigation should return the list to `savedScrollY`. The
  // actual scroll happens in a layout effect, once the list-pane is back in the
  // layout (on mobile it was display:none while the entry was open).
  const pendingRestore = useRef(false);
  // Set while a search pops the history state of the entry it closed, so
  // that popstate is not taken for a Back press.
  const poppingForSearch = useRef(false);
  const [showBuild, setShowBuild] = useState(false);

  useEffect(() => {
    (async () => {
      try {
        await api.init();
        const searches = await api.getSavedSearches();
        store.savedSearches.value = searches;

        const initialQuery = searches.length > 0 ? searches[0].filter : '@3-days-old';
        store.query.value = initialQuery;
        await runSearch(initialQuery);
      } catch {
        store.error.value = 'Could not reach Elfeed backend.';
      }
    })();
  }, []);

  const doSearch = useCallback(async (q) => {
    if (await runSearch(q)) {
      // Fresh results: start at the top rather than a stale offset.
      savedScrollY = 0;
      window.scrollTo(0, 0);
    }
  }, []);

  const onSearch = useCallback(async (q) => {
    store.query.value = q;
    if (store.selectedEntry.value) {
      // Opening the entry pushed a history state; drop it along with the
      // entry, or the next Back press would land on it and do nothing.
      store.selectedEntry.value = null;
      poppingForSearch.current = true;
      history.back();
    }
    await doSearch(q);
  }, [doSearch]);

  const onSelectEntry = useCallback((entry) => {
    // Only stash the list position and push history when coming from the list;
    // switching between entries (desktop two-pane) must not stack history or
    // overwrite the remembered offset.
    if (!store.selectedEntry.value) {
      savedScrollY = window.scrollY;
      history.pushState({ entry: true }, '');
    }
    store.selectedEntry.value = entry;
  }, []);

  // Route both the in-app back button and the browser/system back button
  // through popstate so there is a single dismissal path. Take manual control
  // of scroll restoration so the browser's automatic restore doesn't fight us
  // and clamp the position while the list is still hidden.
  useEffect(() => {
    const prevRestoration = 'scrollRestoration' in history ? history.scrollRestoration : null;
    if (prevRestoration !== null) history.scrollRestoration = 'manual';

    const onPop = () => {
      if (poppingForSearch.current) {
        poppingForSearch.current = false;
        return;
      }
      if (store.selectedEntry.value) {
        pendingRestore.current = true;
        store.selectedEntry.value = null;
      }
    };
    window.addEventListener('popstate', onPop);
    return () => {
      window.removeEventListener('popstate', onPop);
      if (prevRestoration !== null) history.scrollRestoration = prevRestoration;
    };
  }, []);

  // While an entry fills the mobile single-pane view, lock the page to the
  // viewport so only the content iframe scrolls — the outer (list) container
  // behind it has nothing useful to scroll.
  useEffect(() => {
    const mq = window.matchMedia('(max-width: 767px)');
    const update = () => {
      const lock = !!store.selectedEntry.value && mq.matches;
      document.documentElement.classList.toggle('reading', lock);
    };
    update();
    mq.addEventListener('change', update);
    const unsub = store.selectedEntry.subscribe(update);
    return () => {
      mq.removeEventListener('change', update);
      unsub();
      document.documentElement.classList.remove('reading');
    };
  }, []);

  // Restore the list scroll after the list-pane is back in the layout.
  useLayoutEffect(() => {
    if (pendingRestore.current && !store.selectedEntry.value) {
      pendingRestore.current = false;
      window.scrollTo(0, savedScrollY);
    }
  }, [store.selectedEntry.value]);

  const onBack = useCallback(() => {
    history.back();
  }, []);

  const onFeedUpdate = useCallback(async () => {
    store.updating.value = true;
    try {
      await api.feedUpdate();
      await api.feedUpdateDone();
      await doSearch(store.query.value);
    } catch {
      store.error.value = 'Feed update failed.';
    } finally {
      store.updating.value = false;
    }
  }, [doSearch]);

  const selected = store.selectedEntry.value;
  const updating = store.updating.value;
  const error = store.error.value;

  // The title opens the build readout: long-press, or three quick taps. No room
  // in the header for a control, and it is only ever wanted when something
  // looks wrong. The tap count is there because iOS claims long presses on text
  // for its own selection UI, and a device running a stale stylesheet has no
  // `-webkit-touch-callout: none` to stop it — the exact situation the readout
  // exists to diagnose.
  const titleRef = useRef(null);
  useEffect(() => {
    const el = titleRef.current;
    if (!el) return;

    let timer = null;
    let taps = 0;
    let tapReset = null;
    const cancel = () => { clearTimeout(timer); timer = null; };

    const onStart = (e) => {
      // Suppress the selection callout at the source; the title has no other
      // touch behaviour to preserve.
      e.preventDefault();
      cancel();
      timer = setTimeout(() => setShowBuild(true), 600);
      taps += 1;
      clearTimeout(tapReset);
      tapReset = setTimeout(() => { taps = 0; }, 600);
      if (taps >= 3) {
        taps = 0;
        cancel();
        setShowBuild(true);
      }
    };
    const onContext = (e) => { e.preventDefault(); setShowBuild(true); };

    el.addEventListener('touchstart', onStart, { passive: false });
    el.addEventListener('touchend', cancel);
    el.addEventListener('touchmove', cancel);
    el.addEventListener('touchcancel', cancel);
    el.addEventListener('contextmenu', onContext);
    return () => {
      cancel();
      clearTimeout(tapReset);
      el.removeEventListener('touchstart', onStart);
      el.removeEventListener('touchend', cancel);
      el.removeEventListener('touchmove', cancel);
      el.removeEventListener('touchcancel', cancel);
      el.removeEventListener('contextmenu', onContext);
    };
  }, []);

  return (
    <main class={`container-fluid ${selected ? 'reading' : ''}`}>
      {error && <div class="error-banner" role="alert">{error}</div>}
      {showBuild && <BuildInfo onClose={() => setShowBuild(false)} />}
      <header>
        <h1
          ref={titleRef}
          style="-webkit-user-select: none; user-select: none; -webkit-touch-callout: none;"
        >
          Elfeed
        </h1>
        <button
          class="outline secondary update-feeds"
          onClick={onFeedUpdate}
          aria-busy={updating}
          disabled={updating}
        >
          {updating ? 'Updating...' : 'Update feeds'}
        </button>
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
            />
          )}
        </div>
      </div>
    </main>
  );
}
