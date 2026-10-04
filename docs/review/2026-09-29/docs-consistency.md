# Docs consistency review: elfeed-web-ng

Scope: whole repository · Commit: 0e482e5 · Date: 2026-09-29

## Inventory

| File | Class | Reason |
|---|---|---|
| `README.md` | current | Features, install, config, security, dev workflow |
| `CLAUDE.md` | current | Agent instructions: package manager and build/dev commands (overlaps README "Development") |
| `docs/DISCOVERIES.md` | current | Lessons learned. Its "Fix adopted" paragraphs describe mechanisms still in the code; only those present-state claims were checked |
| `docs/2026-04-24-fixes.md` | historical | Dated record of review fixes that refers to a `dev` branch and to "before the fix". Drift not reported |
| `elfeed-web-ng.el` Commentary + docstrings | current | In-code endpoint and API reference |
| `test/elfeed-web-ng-test.el` Commentary | current | How to run the ERT suite |
| `.gitattributes` comment | current | Explains the `merge=ours` rule on `web/**` |
| `LICENSE` | current (legal) | AGPL-3.0 text, consistent with the SPDX header and README |
| `package.json` | current (metadata) | Version 1.0.0 matches `elfeed-web-ng.el` |
| `legacy/*` | historical | Upstream frontend kept for reference (README.md:127) |
| `design/favicon.af` | n/a | Design asset |

Verification: ran the test file's instructions (9/9 pass), probed IPv6 loopback handling in batch Emacs, and confirmed that the `legacy-compat` tag exists.

## DOC-001: README never says how to start the server or enable it

- **Severity:** medium
- **Confidence:** high
- **Location:** `README.md:25-72`, `elfeed-web-ng.el:47-50`, `elfeed-web-ng.el:524-526`, `elfeed-web-ng.el:562-568`
- **Labels:** docs, readme, elisp

The Installation section (README.md:25-62) never mentions `elfeed-web-ng-start`, the only autoloaded entry point. That command starts httpd and sets `elfeed-web-ng-enabled` to t (el:562-568). `elfeed-web-ng-enabled` defaults to nil (el:47). Until it is set, `/elfeed/` answers "Elfeed web interface is disabled" and every API returns 403 (el:282-283, 524-526). The variable appears only in the stop note (README.md:72), not in the Configuration list. Its docstring (el:48) doesn't mention start/stop.

**Why it matters:** someone following the README exactly ends up with a disabled interface and no next step.

**Suggested fix:** add a Usage step: `M-x elfeed-web-ng-start`, then open `http://<host>:<port>/elfeed/`. List `elfeed-web-ng-enabled` under Configuration, and fix its docstring.

**Done when:** the README names `elfeed-web-ng-start` and the URL. The variable appears in the Configuration list, and its docstring mentions start/stop.

## DOC-002: Commentary endpoint list omits the required HTTP methods

- **Severity:** low
- **Confidence:** high
- **Location:** `elfeed-web-ng.el:19-31`, `elfeed-web-ng.el:355-363`, `elfeed-web-ng.el:475-489`, `elfeed-web-ng.el:540-542`
- **Labels:** docs, elisp, api

The Commentary gives a method for `/elfeed/tags` (PUT) and `/elfeed/annotation` (GET/PUT). It gives none for `/elfeed/feed-update` or `/elfeed/mark-all-read`, which accept only POST and return 405 otherwise (el:360, 485, via `--with-method`). The `/favicon.ico` redirect (el:540) is not listed.

**Why it matters:** the header is the only API reference, and a client following it sends GET and gets a 405.

**Suggested fix:** put the method on every endpoint line and add the `/favicon.ico` redirect.

**Done when:** every endpoint in the Commentary shows its method, and the list matches the servlet definitions one for one.

## DOC-003: "Loopback is always permitted" is false for the IPv6 loopback address

- **Severity:** low
- **Confidence:** high
- **Location:** `elfeed-web-ng.el:78-80`, `elfeed-web-ng.el:198-200`, `elfeed-web-ng.el:208-216`, `elfeed-web-ng.el:241-244`, `README.md:83-84`
- **Labels:** docs, security, elisp

The docstring says "Loopback names are always permitted" (el:78), and the README says the allowlist includes "loopback names". The allowlist stores `"::1"` (el:199), while `--strip-port` and `url-host` both keep the brackets (`"[::1]"`). Verified in batch Emacs: `(elfeed-web-ng--host-allowed-p "[::1]:8082")` and `(elfeed-web-ng--origin-allowed-p "http://[::1]:8082")` both return nil.

**Why it matters:** browsing to `http://[::1]:port/elfeed/` gets a 403 that the docs say cannot happen. The fail-closed behavior is safe, so this is a docs/usability issue, not a vulnerability.

**Suggested fix:** normalize the bracketed form (or add `"[::1]"` to the loopback list), or narrow the docs to the names actually accepted.

**Done when:** a test asserts `"[::1]:8082"` is accepted as Host and Origin, or the docs stop claiming all loopback names.

## DOC-004: favicon.ico docstring names the wrong redirect target

- **Severity:** low
- **Confidence:** high
- **Location:** `elfeed-web-ng.el:540-542`
- **Labels:** docs, elisp

The docstring says "Redirect /favicon.ico to /elfeed/favicon.ico", but the code redirects to `/elfeed/icons/favicon_dark.svg`. `web/` has no `favicon.ico`.

**Why it matters:** it sends readers looking for a file that doesn't exist.

**Suggested fix:** name the actual target in the docstring.

**Done when:** the docstring names the path the code redirects to.

## DOC-005: README features and ideas don't match the shipped UI

- **Severity:** low
- **Confidence:** high
- **Location:** `README.md:5-11`, `README.md:120-123`, `src/components/TagActions.jsx:29-61`, `src/components/EntryList.jsx:61-69,111-112`, `src/app.jsx:144-149,210`, `src/public/sw.js:57-68`
- **Labels:** docs, readme, frontend

- **Custom tags:** the README claims "custom tags" management (README.md:9). The UI toggles only `unread`, `★` and `later`; other tags are display-only.
- **Missing features:** Update feeds, mark-all-read, swipe-to-toggle-read, and the build-info panel (long-press or triple-tap the title, app.jsx:144-149) are not listed.
- **Offline idea:** the "Offline support" idea (README.md:123) is already partly implemented: the app shell falls back to the cache (sw.js:57-68).

**Why it matters:** users expect features that don't exist and can't find the diagnostics panel when a build is stale.

**Suggested fix:** reword the tag bullet, add the missing features (including the build-panel gesture), and narrow the offline idea to what remains.

**Done when:** every feature bullet maps to UI code, and the build-panel gesture is documented.

## DOC-006: README says `.gitattributes` keeps "the newer files"; `merge=ours` keeps the checked-out side

- **Severity:** low
- **Confidence:** high
- **Location:** `README.md:118`, `.gitattributes:3`
- **Labels:** docs, readme, build

The README says the rule will "take the newer files in any case". `web/** merge=ours` with `merge.ours.driver true` keeps the current side, whatever its age. During a rebase that is the upstream side, so the replayed commits' `web/` changes are dropped. The README also doesn't say that without the driver configured, Git falls back to a normal merge.

**Why it matters:** someone who trusts "newer" may skip the rebuild and ship a stale bundle.

**Suggested fix:** reword to: "keeps the current branch's `web/` (upstream's during a rebase) without conflict; always rebuild and commit afterwards". Mention the unconfigured-driver case.

**Done when:** the README matches Git's `ours`-driver behavior for both merge and rebase.

See also: PKG-001 (stale-bundle check).

## DOC-007: DISCOVERIES.md uses identifiers that no longer exist

- **Severity:** low
- **Confidence:** high
- **Location:** `docs/DISCOVERIES.md:7`, `docs/DISCOVERIES.md:43-45`, `elfeed-web-ng.el:93`, `vite.config.js:7`, `vite.config.js:26-50`
- **Labels:** docs

- Line 7 names `elfeed-web-ng-data-root`; the variable is `elfeed-web-ng--data-root` (el:93).
- Lines 43-45 describe a "`stampServiceWorker`" plugin that stamps `Date.now()` into `sw.js`. The plugin is actually `stampBuildId` (`'stamp-build-id'`), and it stamps `Date.now().toString(36)` into both `sw.js` and `assets/index.css` (vite.config.js:7,32-50).

**Why it matters:** searching for these names finds nothing. The doc also omits the CSS stamp that the build panel relies on (BuildInfo.jsx:7-10).

**Suggested fix:** correct both names and mention the stylesheet stamp.

**Done when:** every identifier mentioned in DISCOVERIES.md exists in the code.

## DOC-008: The dev proxy's hard-coded target is undocumented and conflicts with the recommended bind

- **Severity:** low
- **Confidence:** high
- **Location:** `README.md:52-62`, `README.md:110-113`, `vite.config.js:78-90`
- **Labels:** docs, readme, dev

The README says `pnpm run dev` proxies "to Emacs backend" but not where. Every proxy entry targets `http://localhost:8082` (vite.config.js:80-89), while the README recommends binding to the Tailscale IP (README.md:52-62). With that setup the backend doesn't listen on localhost, and the dev server's API calls fail.

**Why it matters:** following the security advice and then the dev instructions gives a broken dev server with no explanation.

**Suggested fix:** document the `localhost:8082` target and how to match it, or make it configurable through an env var.

**Done when:** the README names the proxy target and says how to change or match it.

## DOC-009: No documented way to run the tests; the test header has a vague placeholder

- **Severity:** low
- **Confidence:** high
- **Location:** `README.md:104-118`, `test/elfeed-web-ng-test.el:5-8`
- **Labels:** docs, tests

The README's Development section never mentions the ERT suite. The test header uses `-L <deps>` without naming simple-httpd and elfeed. It also describes the suite as "tests for the request-guarding helpers", but the suite now covers static-file serving too (test lines 85-106).

**Why it matters:** without a documented command, contributors are unlikely to run the project's only automated check.

**Suggested fix:** add a "Tests" subsection with the concrete command and its dependencies, and update the header wording.

**Done when:** a contributor can run the suite by copying the command from the README.

See also: TST-004 (script/CI entry point).

## DOC-010: Historical and current docs are mixed in `docs/` with no entry point

- **Severity:** low
- **Confidence:** medium
- **Location:** `docs/2026-04-24-fixes.md:1-3,70,111`, `docs/DISCOVERIES.md:1-3`, `README.md:104-135`, `CLAUDE.md:1-17`
- **Labels:** docs, organization

`docs/` holds a current reference (`DISCOVERIES.md`) next to a dated record that isn't marked historical. That record names things that no longer exist: `elfeed-web-ng-reset`, `elfeed-web-ng-webid-map`, `getAnnotation`, and a `dev` branch. The README links to neither file, and CLAUDE.md repeats the README's dev commands.

**Why it matters:** readers may take the dated file as current guidance, and the useful DISCOVERIES notes are hard to find.

**Suggested fix:** proposed layout:
- `README.md`: user docs, plus a "Further reading" link to `docs/DISCOVERIES.md`.
- `docs/DISCOVERIES.md`: current lessons.
- `docs/history/`: move `2026-04-24-fixes.md` there and start it with "Historical record — may not match current code".
- `CLAUDE.md`: link to the README's Development section instead of repeating the commands.

**Done when:** every file under `docs/` is either linked from the README or sits in a folder whose name marks it historical.
