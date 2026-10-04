# General review: elfeed-web-ng

Scope: whole repository · Commit: 0e482e5 · Date: 2026-09-29

This review found 8 findings: 2 medium and 6 low. The `#N` search-limit override it also found is tracked as SEC-005. The two medium ones are both in the frontend search flow. The following were checked and found fine: JSON encoding of tags and of empty lists, early exit of the search scan at the limit, service-worker handling of non-GET and API requests, and listener cleanup in the components.

## GEN-001: Overlapping searches can show results for the wrong query

- **Severity:** medium
- **Confidence:** high
- **Location:** `src/app.jsx:23-44`, `src/app.jsx:46-58`, `src/app.jsx:60-64`, `src/app.jsx:129-138`
- **Labels:** bug, frontend

`doSearch` assigns `store.entries.value = results` from whichever request finishes last. There is no request token and no AbortController, so a slow earlier search can overwrite a newer one while the UI still shows the newer query. The initial load, the feed-update refresh and user searches all collide this way. `store.loading` is cleared by the first request to finish (`:56`).

**Why it matters:** the list can disagree with the active filter, and swipes then act on the wrong entries.

**Suggested fix:** keep a request token or abort the previous fetch, and apply results and clear `loading` only when the token is still current.

**Done when:** when two searches finish in reverse order, the second query's entries are shown, and `loading` stays true until the latest search settles.

## GEN-002: Search and feed-update failures are silently swallowed

- **Severity:** medium
- **Confidence:** high
- **Location:** `src/app.jsx:46-58`, `src/app.jsx:129-138`, `src/components/EntryList.jsx:137-138`, `src/components/SavedSearches.jsx:19`, `src/components/SearchBar.jsx:12`
- **Labels:** bug, frontend, error-handling

`doSearch` uses `try/finally` with no `catch`, so its rejections reach click and submit handlers that don't handle them, and no error is shown. `onFeedUpdate` has no `catch` either, so a dropped long-poll just resets the button. `handleMarkAllRead` doesn't `await onSearch`, so its `catch` never sees a failed refresh.

**Why it matters:** a failure looks the same as success with no new results.

**Suggested fix:** catch errors in `doSearch` and `onFeedUpdate` and set `store.error`. Await `onSearch` in `handleMarkAllRead`.

**Done when:** failures show an error message and produce no unhandled rejections.

## GEN-003: Swiping an entry leaves the open reader's tag state stale

- **Severity:** low
- **Confidence:** high
- **Location:** `src/components/EntryList.jsx:64-69`, `src/lib/store.js:17-21`, `src/components/TagActions.jsx:16-21`
- **Labels:** bug, frontend

`replaceEntry` updates `store.entries` but not `store.selectedEntry`. In the two-pane layout, after you swipe the open entry, TagActions still shows the old state, and its next toggle is a no-op.

**Why it matters:** the reader's buttons contradict the list, and the next tap is lost.

**Suggested fix:** have `replaceEntry` also update `selectedEntry` when the webid matches.

**Done when:** after swiping the selected entry, the reader's read/unread button reflects the new state.

## GEN-004: Clearing the selection via search leaves a dangling history entry

- **Severity:** low
- **Confidence:** high
- **Location:** `src/app.jsx:60-75`, `src/app.jsx:85-90`, `src/components/EntryList.jsx:138`
- **Labels:** bug, frontend, navigation

`onSelectEntry` pushes a history state. `onSearch` (and mark-all-read, which calls it) sets `selectedEntry = null` without popping that state. Each later Back press fires a `popstate` that `onPop` ignores.

**Why it matters:** Back appears to do nothing, once for every search made while reading.

**Suggested fix:** when a search clears a selection, call `history.back()` or `replaceState`.

**Done when:** after opening an entry, searching, and pressing Back once, you leave the app or return to the previous real history entry.

## GEN-005: Tag changes made in the web UI are neither saved nor signalled to Emacs

- **Severity:** low
- **Confidence:** medium
- **Location:** `elfeed-web-ng.el:355-363`, `elfeed-web-ng.el:395-400`
- **Labels:** bug, backend, persistence

`/tags` and `/mark-all-read` change entries in memory only. Elfeed saves its index on exit, or when the search buffer is quit, killed or saved. Neither endpoint bumps `:last-update`, so an open `*elfeed-search*` buffer stays stale. The user's own config mitigates this with tag hooks, but the package itself does not.

**Why it matters:** if Emacs crashes, read-state changes are lost, and Emacs and the web UI disagree.

**Suggested fix:** schedule a debounced `elfeed-db-save`, and refresh the search buffer if it exists.

**Done when:** without user hooks, a web tag change reaches disk within a bounded time and shows up in the Emacs search buffer.

## GEN-006: `feed-update-done` can park a request with nothing to answer it

- **Severity:** low
- **Confidence:** high
- **Location:** `elfeed-web-ng.el:470-473`, `elfeed-web-ng.el:491-498`
- **Labels:** bug, backend, long-poll

When the queue is non-empty, the endpoint parks the process. Only `/feed-update` starts the monitor, so a long-poll that arrives during an update started from Emacs is never answered. There is no timeout either.

**Why it matters:** the request hangs until some unrelated POST happens.

**Suggested fix:** call `(elfeed-web-ng--monitor-feed-update)` in the parking branch.

**Done when:** an ERT test shows that a parked request is answered once the queue drains, with no `/feed-update` call.

See also: TST-007.

## GEN-007: `/elfeed/things/<webid>` returns 500 for an unknown webid

- **Severity:** low
- **Confidence:** high
- **Location:** `elfeed-web-ng.el:159-161`, `elfeed-web-ng.el:298-301`
- **Labels:** bug, backend, api

A failed lookup returns nil, and `cl-etypecase` in `elfeed-web-ng-for-json` signals on nil, which becomes a 500. Other endpoints answer 404 in the same case.

**Why it matters:** clients can't tell "not found" from a server fault.

**Suggested fix:** send `(elfeed-web-ng--send-json-error 404)` when the lookup returns nil.

**Done when:** an unknown but well-formed webid returns 404, and a test covers it.

See also: ORG-004 (the endpoint has no caller).

## GEN-008: The reader renders error bodies as entry content

- **Severity:** low
- **Confidence:** high
- **Location:** `src/components/EntryContent.jsx:76-83`
- **Labels:** bug, frontend, error-handling

The content fetch calls `res.text()` without checking `res.ok`, so a 404 or 403 body is shown as the article. A network error shows a blank frame.

**Why it matters:** a failed load looks like broken content.

**Suggested fix:** throw on `!res.ok`, and render a "Could not load content" message.

**Done when:** a content request that returns 404 shows an explicit error message.
