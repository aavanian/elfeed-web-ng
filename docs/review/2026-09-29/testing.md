# Testing review: elfeed-web-ng

Scope: whole repository · Commit: 0e482e5 · Date: 2026-09-29

- **Framework:** ERT, one file: `test/elfeed-web-ng-test.el` (9 tests). No `check.sh`, Makefile, CI, or `test` script in `package.json`. The frontend has no test framework and no tests.
- **Run:** `emacs --batch -L straight/build-31.1/elfeed -L straight/build-31.1/simple-httpd -L . -l test/elfeed-web-ng-test.el -f ert-run-tests-batch-and-exit` → **9/9 passed** (0.002 s).
- **Coverage:** not measured (no tooling configured). By inspection, 7 of ~25 functions in `elfeed-web-ng.el` are exercised, all of them pure request-guard predicates plus the symlink branch of `--serve-static`. No servlet is tested; no JS is tested.
- **Existing test quality:** good. The tests make concrete assertions, cover negative cases, and none are skipped or flaky-looking.

## TST-001: Add request-level tests proving each servlet enforces its guards

- **Severity:** high
- **Confidence:** high
- **Location:** `elfeed-web-ng.el:271-296`, `elfeed-web-ng.el:298-498`, `elfeed-web-ng.el:519-538`, `test/elfeed-web-ng-test.el:54-80`
- **Labels:** testing, security, server

Each of about 10 servlets applies the Host/Origin/enabled guard (`elfeed-web-ng--with`, :271-284) and the method guard (`--with-method`, :286-296) by hand. The tests check the predicates in isolation only (:54-80). No test calls a servlet with a request alist, so nothing proves any of these:
- `GET /elfeed/mark-all-read` returns 405 (:360).
- A foreign Origin is rejected on `PUT /tags` (:375).
- `/content/` sends `Content-Security-Policy: sandbox` (:326-328).
- The static servlet checks Host (:522).

**Why it matters:** if a servlet loses its wrapper, or a refactor drops the CSP header, the DNS-rebinding, CSRF or stored-XSS protections disappear while every test still passes.

**Suggested fix:** add an ERT helper that binds `httpd-request` (method, Host, Origin, Content) and stubs `httpd-send-header`/`httpd-log` with `cl-letf` to capture status and headers. Use it to call the `httpd/elfeed/...` functions directly, with one table-driven test per endpoint: bad Host, bad Origin, disabled mode, wrong method, success.

**Done when:** every servlet has a test asserting 403 on a disallowed Host. Every state-changing endpoint (`tags`, `mark-all-read`, `feed-update`, annotation PUT) asserts 403 on a foreign Origin and 405 on GET. `/content/` has a test asserting the CSP header.

## TST-002: Test /elfeed/tags input validation and malformed-body handling

- **Severity:** medium
- **Confidence:** high
- **Location:** `elfeed-web-ng.el:181-187`, `elfeed-web-ng.el:375-400`, `elfeed-web-ng.el:444-449`
- **Labels:** testing, input-validation, server

`elfeed-web-ng--valid-tag-p` (:181-187) and the `/tags` status ladder (:386-392) have no tests, and the gap already hides errors:
- The body is decoded before the method check (:377-378), and `(decode-coding-string nil 'utf-8)` signals. So a bodyless GET gets a generic 500 where the code intends a 405 (verified in batch Emacs).
- `{"entries": 5}` gets a 500 where a 400 is intended (verified).
- The annotation PUT decodes the body the same way (:444-445).

**Why it matters:** this endpoint takes user input and writes to the database, and malformed input already produces 500s.

**Suggested fix:** unit-test `valid-tag-p` with lengths 64 and 65, `★`, a space, `/`, and a non-string. Using the TST-001 harness, add request tests for `/tags` covering no body, invalid JSON, an invalid tag, an unknown webid, a non-array `entries`, and a valid round-trip on a temporary `elfeed-db`.

**Done when:** each case above asserts its exact status (405, 400, 400, 404, 400, 200), and the success case asserts the returned tags.

See also: SEC-004, ORG-006.

## TST-003: Test webid generation, lookup, and index caching together

- **Severity:** medium
- **Confidence:** high
- **Location:** `elfeed-web-ng.el:111-157`, `test/elfeed-web-ng-test.el:107-122`
- **Labels:** testing, server, performance

`elfeed-web-ng-make-webid`, `--ensure-webid-index` and `elfeed-web-ng-lookup` have no tests. `--ensure-webid-index` is meant to rescan at most once per `:last-update` stamp (:143-149). The validator test hardcodes the alphabet (:109-111) and never checks that the output of `make-webid` passes the validator.

**Why it matters:** every lookup goes through this code. Drift between producer and validator makes every entry return 404, and a stamp bug brings back a full-database rescan on every request.

**Suggested fix:** on a temporary `elfeed-db`, assert:
- `(valid-webid-p (make-webid x))` holds;
- lookup resolves through the index after the map is cleared;
- a second miss at the same stamp does not rescan;
- a changed stamp triggers a rebuild.

**Done when:** those four assertions exist and pass.

## TST-004: Add a test script and a documented entry point for the ERT suite

- **Severity:** medium
- **Confidence:** high
- **Location:** `test/elfeed-web-ng-test.el:5-8`, `package.json:5-9`
- **Labels:** testing, tooling

The only run instructions are in the test file's header, and they say `-L <deps>` without naming the dependencies (:7). There is no `check.sh`, Makefile, CI, or `test` script, so the suite never runs automatically.

**Why it matters:** tests that don't run by default stop protecting the security guards they cover.

**Suggested fix:** add a `check.sh` or Makefile target that runs ERT with configurable dependency paths (e.g. `ELFEED_DIR`, `HTTPD_DIR`). Optionally wire it to `pnpm test` and a minimal CI workflow.

**Done when:** one documented command runs the full suite and exits non-zero on failure.

## TST-005: Add tests for the frontend (service worker cache rules, API client)

- **Severity:** medium
- **Confidence:** high
- **Location:** `src/public/sw.js:17-26`, `src/public/sw.js:44-70`, `src/lib/api.js:7-23`, `src/lib/store.js:17-21`, `package.json:10-19`
- **Labels:** testing, frontend

No JS/JSX has a test, and there is no test runner. The riskiest untested logic:
- `isStaticAsset` in `sw.js` decides what is cached; a mistake serves stale feed or tag data.
- `api.js` `init()` falls back to a `legacy` capability set on error, which gates features.
- `replaceEntry` backs every in-place edit.

**Why it matters:** service worker caching bugs persist on client devices and are hard to diagnose.

**Suggested fix:** add Vitest and a `test` script. Unit-test `isStaticAsset` (export it first), `init`/`hasFeature` with a stubbed `fetch`, and `replaceEntry`.

**Done when:** `pnpm test` asserts `isStaticAsset` is true for asset and icon paths and false for `/elfeed/search`, `/elfeed/tags` and `/elfeed/things/x`. It also covers `init` on ok, non-ok and thrown fetch.

## TST-006: Test the JSON shape produced by elfeed-web-ng-for-json

- **Severity:** low
- **Confidence:** high
- **Location:** `elfeed-web-ng.el:159-179`, `src/lib/format.js:5`
- **Labels:** testing, api-contract

The serializer defines the frontend contract, and no test covers it:
- `:date` is in milliseconds (:166).
- `:tags` and `:enclosures` fall back to `[]` (:170-171).
- `:content` is a ref or nil.
- `:feed` is nested.

**Why it matters:** a change to this shape breaks the UI without any server-side test failing.

**Suggested fix:** build an entry and a feed with elfeed constructors, `json-encode` the result of `for-json`, and parse it back.

**Done when:** a test asserts that empty tags and enclosures encode as `[]`, that date is seconds × 1000, and that the nested feed carries a webid.

## TST-007: Test the feed-update poll chain and the long-poll endpoint

- **Severity:** low
- **Confidence:** high
- **Location:** `elfeed-web-ng.el:347-353`, `elfeed-web-ng.el:456-498`
- **Labels:** testing, concurrency, server

`--check-queue-done`, `--monitor-feed-update`, `--notify-feed-done` and the `feed-update`/`feed-update-done` servlets have no tests. That covers timer de-duplication (:456-458, :472), skipping a fetch while one is in flight (:486), and answering immediately on an empty queue (:496-497).

**Why it matters:** timer-chain bugs stack polls, or leave long-poll clients hanging forever.

**Suggested fix:** stub `elfeed-queue-count-total`, `run-at-time` and `elfeed-update` with `cl-letf`, then assert timer de-duplication, the in-flight skip, and draining of waiting clients.

**Done when:** tests prove that two monitor calls schedule at most one timer, that the waiting list empties on completion, and that `feed-update-done` responds immediately on an empty queue.

## TST-008: Test /elfeed/search with a missing or empty query

- **Severity:** low
- **Confidence:** medium
- **Location:** `elfeed-web-ng.el:331-345`
- **Labels:** testing, server

The search servlet builds its filter with `(format "#%d %s" elfeed-web-ng-limit q)` (:335). When `q` is nil this produces `"#512 nil"` (verified in batch Emacs). No test covers search or the limit cap. Not yet confirmed: whether `defservlet*` binds an absent `q` to nil.

**Why it matters:** a request with no query can quietly return wrong results.

**Suggested fix:** add request tests for `q` absent, empty and `+unread`, plus one with more entries than a small `elfeed-web-ng-limit`.

**Done when:** tests assert that the result count stays at or under the limit and that the missing-`q` behavior is explicit.

See also: SEC-005.
