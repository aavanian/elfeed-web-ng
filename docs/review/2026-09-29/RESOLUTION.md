# Resolution of the 2026-09-29 review

Each finding of the [review](README.md) is listed with what resolved it: the
commit that fixed it, or the reason it needed no change. Commits are named by
subject, since hashes change when a branch is rebased.

| ID | Resolution |
|---|---|
| TST-001 | `test(server): prove every servlet enforces its request guards` |
| TST-002 | `fix(tags): answer malformed tag requests with 4xx instead of 500` |
| TST-003 | `test(webid): cover webid generation, lookup and index caching` |
| TST-004 | `test(tooling): add check.sh as the single test entry point` |
| TST-005 | `test(frontend): add a node:test suite for the service worker and store`, plus the `init()` cases in `refactor(api): stop negotiating features that are always present` |
| TST-006 | `test(json): pin the entry JSON shape the frontend relies on` |
| TST-007 | `fix(feed-update): answer long polls parked during an Emacs-side update` |
| TST-008 | `fix(search): keep the result limit out of the client's reach` |
| SEC-001 | `fix(security): require the Origin to be the server's own origin`. Deviation: loopback names stay in the Host allowlist for a non-loopback bind. The same-origin rule already keeps other local services out, and keeping them preserves SSH-tunnel access. |
| SEC-002 | `docs(security): say the allowlist covers /elfeed/ only` (documentation only, by owner decision: a global filter would also apply to other packages' servlets) |
| SEC-003 | server: `fix(privacy): send Referrer-Policy: no-referrer with the app and content`; client: `fix(privacy): forbid a Referer from inside the reader frame` (WebKit leaked it, Chromium did not) |
| SEC-004 | `fix(security): validate request bodies before acting on them` |
| SEC-005 | `fix(search): keep the result limit out of the client's reach` |
| ORG-001 | `refactor(api): stop negotiating features that are always present` |
| ORG-002 | `refactor(tags): toggle a tag through one shared helper` |
| ORG-003 | Kept by owner decision, for a planned theme toggle: `style(theme): explain why the explicit dark palette is kept`. light-dark() would merge the copies, but browsers without it (Safari before 17.5) would lose every colour. |
| ORG-004 | `refactor(api): drop the endpoints no client calls` |
| ORG-005 | `chore(repo): drop the legacy/ frontend` |
| ORG-006 | `fix(tags): answer malformed tag requests with 4xx instead of 500` |
| ORG-007 | `refactor(layout): express the selection state with one class` |
| ORG-008 | `refactor(content): leave entry content styling to the reader` |
| ORG-009 | `refactor(sw): let API requests bypass the service worker` |
| ORG-010 | `style(entry-actions): drop margins that were always overridden` |
| DOC-001 | `docs(readme): say how to start the server and where to find it` |
| DOC-002 | `docs(api): give every endpoint its method in the Commentary` |
| DOC-003 | `fix(security): require the Origin to be the server's own origin` (code fixed to match the docs) |
| DOC-004 | `docs(api): give every endpoint its method in the Commentary` |
| DOC-005 | `docs(readme): list the features the UI actually has` |
| DOC-006 | `docs(readme): describe what merge=ours actually keeps` |
| DOC-007 | `docs(discoveries): use current identifiers, and record new lessons` |
| DOC-008 | `fix(dev): make the dev proxy target configurable and pass the origin check` (also fixes the dev-proxy breakage SEC-001 introduced) |
| DOC-009 | `test(tooling): add check.sh as the single test entry point` |
| DOC-010 | `docs: separate historical records and give docs/ an entry point` |
| PKG-001 | `build(check): fail when the committed web/ bundle is stale` |
| PKG-002 | Won't fix: Emacs 29.2 is the project's deliberate support floor, not a technical requirement of the code. |
| PKG-003 | `chore(package): complete the library header and pin the version` |
| PKG-004 | `chore(package): declare the license and require pnpm 12` (devEngines rather than packageManager/Corepack; pnpm 12 enforces it and does not enforce engines.pnpm) |
| PKG-005 | `chore(package): complete the library header and pin the version` |
| GEN-001 | `fix(search): show the latest search, and say when a search fails` |
| GEN-002 | `fix(search): show the latest search, and say when a search fails`, `fix(ui): report failed feed updates, and await the mark-all-read refresh` |
| GEN-003 | `fix(reader): keep the open entry in step with swipes in the list` |
| GEN-004 | `fix(navigation): drop the entry's history state when a search closes it` |
| GEN-005 | `feat(emacs): show web tag changes in the open search buffer`. Saving is left to Elfeed and the user's hooks by owner decision; the README explains it. |
| GEN-006 | `fix(feed-update): answer long polls parked during an Emacs-side update` |
| GEN-007 | Superseded: the `/elfeed/things` endpoint was removed (`refactor(api): drop the endpoints no client calls`) |
| GEN-008 | `fix(reader): say so when an entry's content fails to load` |

TST-005: the `init()` cases of `api.js` were added with ORG-001, which changed
how `init()` treats a failed `/elfeed/api`.
