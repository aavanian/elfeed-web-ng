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
| TST-005 | `test(frontend): add a node:test suite for the service worker and store` |
| TST-006 | `test(json): pin the entry JSON shape the frontend relies on` |
| TST-007 | `fix(feed-update): answer long polls parked during an Emacs-side update` |
| TST-008 | `fix(search): keep the result limit out of the client's reach` |
| SEC-001 | `fix(security): require the Origin to be the server's own origin`. Deviation: loopback names stay in the Host allowlist for a non-loopback bind. The same-origin rule already keeps other local services out, and keeping them preserves SSH-tunnel access. |
| SEC-002 | `docs(security): say the allowlist covers /elfeed/ only` (documentation only, by owner decision: a global filter would also apply to other packages' servlets) |
| SEC-003 | server: `fix(privacy): send Referrer-Policy: no-referrer with the app and content`; client: planned, frontend-fixes |
| SEC-004 | `fix(security): validate request bodies before acting on them` |
| SEC-005 | `fix(search): keep the result limit out of the client's reach` |
| ORG-001 | planned: server-api-cleanup |
| ORG-002 | planned: frontend-fixes |
| ORG-003 | planned: css-cleanup |
| ORG-004 | planned: server-api-cleanup |
| ORG-005 | planned: docs-and-packaging |
| ORG-006 | `fix(tags): answer malformed tag requests with 4xx instead of 500` |
| ORG-007 | planned: css-cleanup |
| ORG-008 | planned: server-api-cleanup |
| ORG-009 | planned: frontend-fixes |
| ORG-010 | planned: css-cleanup |
| DOC-001 | planned: docs-and-packaging |
| DOC-002 | planned: server-api-cleanup |
| DOC-003 | `fix(security): require the Origin to be the server's own origin` (code fixed to match the docs) |
| DOC-004 | planned: server-api-cleanup |
| DOC-005 | planned: docs-and-packaging |
| DOC-006 | planned: docs-and-packaging |
| DOC-007 | planned: docs-and-packaging |
| DOC-008 | planned: docs-and-packaging |
| DOC-009 | `test(tooling): add check.sh as the single test entry point` |
| DOC-010 | planned: docs-and-packaging |
| PKG-001 | `build(check): fail when the committed web/ bundle is stale` |
| PKG-002 | planned: server-api-cleanup |
| PKG-003 | planned: server-api-cleanup |
| PKG-004 | planned: docs-and-packaging |
| PKG-005 | planned: server-api-cleanup |
| GEN-001 | planned: frontend-fixes |
| GEN-002 | planned: frontend-fixes |
| GEN-003 | planned: frontend-fixes |
| GEN-004 | planned: frontend-fixes |
| GEN-005 | planned: server-api-cleanup |
| GEN-006 | `fix(feed-update): answer long polls parked during an Emacs-side update` |
| GEN-007 | planned: server-api-cleanup |
| GEN-008 | planned: frontend-fixes |

TST-005: the `init()` cases of `api.js` are added with ORG-001, which changes
how `init()` treats a failed `/elfeed/api`.
