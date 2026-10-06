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
| SEC-003 | server: `fix(privacy): send Referrer-Policy: no-referrer with the app and content`; client: planned, frontend-fixes |
| SEC-004 | `fix(security): validate request bodies before acting on them` |
| SEC-005 | `fix(search): keep the result limit out of the client's reach` |
| ORG-001 | `refactor(api): stop negotiating features that are always present` |
| ORG-002 | planned: frontend-fixes |
| ORG-003 | planned: css-cleanup |
| ORG-004 | `refactor(api): drop the endpoints no client calls` |
| ORG-005 | planned: docs-and-packaging |
| ORG-006 | `fix(tags): answer malformed tag requests with 4xx instead of 500` |
| ORG-007 | planned: css-cleanup |
| ORG-008 | `refactor(content): leave entry content styling to the reader` |
| ORG-009 | planned: frontend-fixes |
| ORG-010 | planned: css-cleanup |
| DOC-001 | planned: docs-and-packaging |
| DOC-002 | `docs(api): give every endpoint its method in the Commentary` |
| DOC-003 | `fix(security): require the Origin to be the server's own origin` (code fixed to match the docs) |
| DOC-004 | `docs(api): give every endpoint its method in the Commentary` |
| DOC-005 | planned: docs-and-packaging |
| DOC-006 | planned: docs-and-packaging |
| DOC-007 | planned: docs-and-packaging |
| DOC-008 | planned: docs-and-packaging |
| DOC-009 | `test(tooling): add check.sh as the single test entry point` |
| DOC-010 | planned: docs-and-packaging |
| PKG-001 | `build(check): fail when the committed web/ bundle is stale` |
| PKG-002 | Won't fix: Emacs 29.2 is the project's deliberate support floor, not a technical requirement of the code. |
| PKG-003 | `chore(package): complete the library header and pin the version` |
| PKG-004 | planned: docs-and-packaging |
| PKG-005 | `chore(package): complete the library header and pin the version` |
| GEN-001 | planned: frontend-fixes |
| GEN-002 | planned: frontend-fixes |
| GEN-003 | planned: frontend-fixes |
| GEN-004 | planned: frontend-fixes |
| GEN-005 | `feat(emacs): show web tag changes in the open search buffer`. Saving is left to Elfeed and the user's hooks by owner decision; the README explains it. |
| GEN-006 | `fix(feed-update): answer long polls parked during an Emacs-side update` |
| GEN-007 | Superseded: the `/elfeed/things` endpoint was removed (`refactor(api): drop the endpoints no client calls`) |
| GEN-008 | planned: frontend-fixes |

TST-005: the `init()` cases of `api.js` were added with ORG-001, which changed
how `init()` treats a failed `/elfeed/api`.
