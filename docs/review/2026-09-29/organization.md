# Organization review: elfeed-web-ng

Scope: whole repository · Commit: 0e482e5 · Date: 2026-09-29

The main themes:
- leftover upstream-compatibility scaffolding;
- duplicated logic and CSS;
- dead code paths: an unread capabilities signal, uncalled endpoints, the `legacy/` frontend, and a cache fallback that can never match.

Every CSS class selector in `src/styles/app.css` is referenced from JSX. `src/lib/format.js`, `store.replaceEntry`, `design/favicon.af` and the `.nosearch` markers were checked and are all in use.

## ORG-001: Remove upstream-compat capability negotiation that no longer applies

- **Severity:** medium
- **Confidence:** high
- **Location:** `src/lib/api.js:5-23`, `src/lib/api.js:56`, `src/lib/store.js:9`, `src/app.jsx:26-27`, `elfeed-web-ng.el:402-414`
- **Labels:** organization, frontend, backend

The README (README.md:15-23) says the UI now requires the elfeed-web-ng backend. The frontend still negotiates as if it might be talking to upstream:
- `init()` falls back to `{ server: 'legacy', features: [] }` (api.js:13,16).
- `getSavedSearches` guards on `hasFeature('saved-searches')` (api.js:56), which the backend always advertises (el:410).
- The backend also always advertises `"tags"` and `"feed-update-done"` (el:411-412), and nothing reads either one. Only `"annotations"` is conditional (el:413-414).
- `store.capabilities` (app.jsx:27) is written but never read, and it duplicates the module-level variable in api.js:5.

**Why it matters:** the compat layer suggests upstream support that no longer exists, and it is maintained in two layers.

**Suggested fix:**
- Delete `store.capabilities` and the assignment at app.jsx:27.
- Drop the `'legacy'` fallback and the `saved-searches` guard.
- Reduce `/elfeed/api` features to the conditional `"annotations"` flag.

**Done when:** the only capabilities holder left in `src` is the one in api.js, and `/elfeed/api` lists only the features whose value can change.

## ORG-002: Share the tag-toggle logic between swipe and TagActions

- **Severity:** medium
- **Confidence:** high
- **Location:** `src/components/EntryList.jsx:61-69`, `src/components/TagActions.jsx:16-21`
- **Labels:** organization, frontend

Both components run the same toggle steps:
- compute `add`/`remove` from "has tag?";
- call `api.updateTags(add, remove, [entry.webid])`;
- rebuild `tags` with filter/spread.

The only difference is that EntryList hard-codes `'unread'`.

**Why it matters:** any change to how a toggle updates an entry (e.g. using the tags the server returns) has to be made in two places.

**Suggested fix:** add a `toggleTag(entry, tag)` helper (e.g. in `src/lib/api.js`) that returns the updated entry, and call it from both components.

**Done when:** exactly one place in `src/` builds add/remove arrays and the new tag list.

## ORG-003: Delete the duplicated, unreachable dark palette block

- **Severity:** medium
- **Confidence:** high
- **Location:** `src/styles/app.css:12`, `src/styles/app.css:47-83`, `src/styles/app.css:85-119`
- **Labels:** organization, css

The Solarized Dark variables appear twice, as two identical 34-variable blocks:
- under `@media (prefers-color-scheme: dark) { :root:not([data-theme]) }` (48-83);
- under `[data-theme=dark]` (86-119).

Nothing in `src/` sets `data-theme`. So the second block never applies, and the `:not([data-theme…])` qualifiers always match.

**Why it matters:** every palette change has to be made twice, and one of the copies is never used.

**Suggested fix:** remove lines 85-119 and simplify the selectors at 12 and 49 to `:root`, unless a theme toggle is planned.

**Done when:** each palette is declared once, and light and dark rendering are unchanged.

## ORG-004: Remove or document API endpoints that no client calls

- **Severity:** low
- **Confidence:** medium
- **Location:** `elfeed-web-ng.el:298-301`, `elfeed-web-ng.el:436-440`, `vite.config.js:81`
- **Labels:** organization, backend

Two endpoints have no caller:
- `/elfeed/things/:webid` has no caller in `src/` or `legacy/`.
- The GET branch of `/elfeed/annotation/:webid` is unused. The frontend only PUTs (api.js:67-76) and reads annotations from the search payload (el:172-173).

The dev proxy still forwards `/elfeed/things`.

**Why it matters:** these endpoints still have to be maintained and secured, and nothing uses them.

**Suggested fix:** the owner decides which way to go:
- remove both (servlet, GET branch, the Commentary line at el:24, the proxy entry);
- or document them in the README as a supported public API.

**Done when:** every servlet either has a caller in `src/` or is documented as external API.

## ORG-005: Drop the legacy/ frontend, which cannot run against this backend

- **Severity:** low
- **Confidence:** medium
- **Location:** `legacy/elfeed.js:50`, `legacy/elfeed.js:67`, `legacy/index.html:61`, `README.md:127`
- **Labels:** organization, repo-layout

`legacy/` is kept "for reference" (README:127), but it no longer works with this backend:
- it long-polls `/elfeed/update` (elfeed.js:50), which does not exist here;
- it GETs mark-all-read (elfeed.js:67), which now returns 405 (el:360).

Git history and the `legacy-compat` tag already preserve these files.

**Why it matters:** the dead code needs its own `.nosearch`, and readers may take it for a supported fallback.

**Suggested fix:** delete `legacy/` and point README:127 at the upstream repo or the tag, unless the owner prefers to keep the files in-tree.

**Done when:** `legacy/` is gone and the README reference is updated, or the owner has decided to keep it.

## ORG-006: Factor request-body parsing and method checks in the elisp servlets

- **Severity:** low
- **Confidence:** high
- **Location:** `elfeed-web-ng.el:286-296`, `elfeed-web-ng.el:376-392`, `elfeed-web-ng.el:396`, `elfeed-web-ng.el:444-447`
- **Labels:** organization, backend

- **Body parsing is duplicated.** `(decode-coding-string (cadr (assoc "Content" httpd-request)) 'utf-8)` followed by `(ignore-errors (json-read-from-string …))` appears in both `elfeed/tags` and `elfeed/annotation`.
- **The PUT check is hand-written.** `elfeed/tags` checks for PUT inside its `cond` (388) instead of using `elfeed-web-ng--with-method`.
- **Webids are recomputed.** At 396 it calls `elfeed-web-ng-make-webid` again for webids the request already supplied (382).

**Why it matters:** the duplicated error handling can drift. The mis-ordered decode already causes a 500 (see TST-002).

**Suggested fix:**
- Add `elfeed-web-ng--request-json`.
- Wrap `elfeed/tags` in `(elfeed-web-ng--with-method "PUT" …)`.
- Pair `webids` with `entries` instead of recomputing them.

**Done when:** Content decoding and JSON parsing appear once in the file, and `elfeed/tags` uses `--with-method`.

## ORG-007: Use one class for the "entry selected" state

- **Severity:** low
- **Confidence:** high
- **Location:** `src/app.jsx:105`, `src/app.jsx:194`, `src/app.jsx:214`, `src/styles/app.css:180-190`, `src/styles/app.css:424-446`
- **Labels:** organization, frontend, naming

Three classes express one state:
- `main.reading` (app.jsx:194);
- `.app-layout.has-selection` (214);
- `html.reading` (105, mobile only, set from an effect).

The first two come from the same `selected` value on nested elements. `reading` also means different things on `html` (mobile only) and on `main` (every width).

**Why it matters:** three names for one state make the layout CSS hard to follow.

**Suggested fix:** drop `has-selection` in favor of `main.reading`, and optionally rename the `html` class (e.g. `reading-locked`).

**Done when:** one class name expresses the selection state on `main` and its descendants, and the layout is unchanged.

## ORG-008: Remove duplicated content-page styling in server and client

- **Severity:** low
- **Confidence:** high
- **Location:** `elfeed-web-ng.el:309-321`, `src/components/EntryContent.jsx:10-23`, `src/components/EntryContent.jsx:63`
- **Labels:** organization, backend, frontend

The server wraps content in `<html><head><style>` with Solarized colors (el:309-321). The client keeps only `doc.body.innerHTML` (EntryContent.jsx:63) and applies its own `CONTENT_STYLE` with the same colors. The server styling therefore matters only when `/elfeed/content/<ref>` is opened directly, which the app never does.

**Why it matters:** the same palette is maintained in two languages.

**Suggested fix:** reduce the server response to `<meta charset>` plus the content, keeping the CSP header. Alternatively, keep the wrapper and add a comment saying it exists only for direct navigation.

**Done when:** the content colors are defined in one place, or a comment justifies the server copy.

## ORG-009: Remove the service worker cache fallback for API calls, which can never match

- **Severity:** low
- **Confidence:** high
- **Location:** `src/public/sw.js:48-55`
- **Labels:** organization, frontend

Non-static `/elfeed/` paths go through `fetch(request).catch(() => caches.match(request))`. API responses are never cached: `cache.put` is only in the static branch (59-66), and `STATIC_ASSETS` holds only static paths (8-11). So `caches.match` always resolves `undefined`.

**Why it matters:** the code looks like an offline fallback for API calls, but it does nothing.

**Suggested fix:** `return;` without `respondWith` in that branch, which is what the "never cached" comment already describes.

**Done when:** the API branch has no `caches.match`, and API behavior online and offline is unchanged.

## ORG-010: Remove CSS declarations that more specific rules always override

- **Severity:** low
- **Confidence:** high
- **Location:** `src/styles/app.css:380-386`, `src/styles/app.css:395-400`, `src/styles/app.css:464-468`, `src/components/EntryContent.jsx:113-116`
- **Labels:** organization, css

`TagActions` and `AnnotationEditor` are rendered only inside `.entry-actions` (EntryContent.jsx:113-116). So two base margins are always cancelled:
- `.tag-actions { margin-bottom: 0.75rem }` (399) by `.entry-actions .tag-actions { margin-bottom: 0 }` (380-382);
- `.annotation-toggle { margin-top: 0.5rem }` (467) by `.entry-actions .annotation-toggle { margin-top: 0 }` (384-386).

**Why it matters:** these declarations never take effect, and the override rules exist only to cancel them.

**Suggested fix:** delete both base margins and both override rules.

**Done when:** neither margin is declared and then overridden, and the entry-actions row renders the same.
