# Full review: elfeed-web-ng

Scope: whole repository (git-tracked files, excluding `docs/review/`) · Commit: 0e482e5 (clean tree) · Date: 2026-09-29

| Category | Critical | High | Medium | Low | Total |
|---|---|---|---|---|---|
| [Security](security.md) | 0 | 0 | 0 | 5 | 5 |
| [Organization](organization.md) | 0 | 0 | 3 | 7 | 10 |
| [Docs consistency](docs-consistency.md) | 0 | 0 | 1 | 9 | 10 |
| [Testing](testing.md) | 0 | 1 | 4 | 3 | 8 |
| [Packaging](packaging.md) | 0 | 0 | 0 | 5 | 5 |
| [General](general.md) | 0 | 0 | 2 | 6 | 8 |
| **Total** | 0 | 1 | 10 | 35 | 46 |

Duplicates merged:
- The README wording about `merge=ours` is kept as DOC-006 (also found by packaging).
- The `#N` search-limit override is kept as SEC-005 (also found by general).

## High

- TST-001: [Add request-level tests proving each servlet enforces its guards](testing.md#tst-001-add-request-level-tests-proving-each-servlet-enforces-its-guards)

## Medium

- ORG-001: [Remove upstream-compat capability negotiation that no longer applies](organization.md#org-001-remove-upstream-compat-capability-negotiation-that-no-longer-applies)
- ORG-002: [Share the tag-toggle logic between swipe and TagActions](organization.md#org-002-share-the-tag-toggle-logic-between-swipe-and-tagactions)
- ORG-003: [Delete the duplicated, unreachable dark palette block](organization.md#org-003-delete-the-duplicated-unreachable-dark-palette-block)
- DOC-001: [README never says how to start the server or enable it](docs-consistency.md#doc-001-readme-never-says-how-to-start-the-server-or-enable-it)
- TST-002: [Test /elfeed/tags input validation and malformed-body handling](testing.md#tst-002-test-elfeedtags-input-validation-and-malformed-body-handling)
- TST-003: [Test webid generation, lookup, and index caching together](testing.md#tst-003-test-webid-generation-lookup-and-index-caching-together)
- TST-004: [Add a test script and a documented entry point for the ERT suite](testing.md#tst-004-add-a-test-script-and-a-documented-entry-point-for-the-ert-suite)
- TST-005: [Add tests for the frontend (service worker cache rules, API client)](testing.md#tst-005-add-tests-for-the-frontend-service-worker-cache-rules-api-client)
- GEN-001: [Overlapping searches can show results for the wrong query](general.md#gen-001-overlapping-searches-can-show-results-for-the-wrong-query)
- GEN-002: [Search and feed-update failures are silently swallowed](general.md#gen-002-search-and-feed-update-failures-are-silently-swallowed)

## Low

- SEC-001: [Origin check ignores port and always admits loopback (CSRF)](security.md#sec-001-origin-check-ignores-port-and-always-admits-loopback-csrf)
- SEC-002: [Paths outside /elfeed/ bypass the Host/Origin allowlist](security.md#sec-002-paths-outside-elfeed-bypass-the-hostorigin-allowlist)
- SEC-003: [Remote subresources in entry content leak the server address via Referer](security.md#sec-003-remote-subresources-in-entry-content-leak-the-server-address-via-referer)
- SEC-004: [JSON request bodies are not validated (symbol interning, types, size)](security.md#sec-004-json-request-bodies-are-not-validated-symbol-interning-types-size)
- SEC-005: [Search result limit can be overridden from the query string](security.md#sec-005-search-result-limit-can-be-overridden-from-the-query-string)
- ORG-004: [Remove or document API endpoints that no client calls](organization.md#org-004-remove-or-document-api-endpoints-that-no-client-calls)
- ORG-005: [Drop the legacy/ frontend, which cannot run against this backend](organization.md#org-005-drop-the-legacy-frontend-which-cannot-run-against-this-backend)
- ORG-006: [Factor request-body parsing and method checks in the elisp servlets](organization.md#org-006-factor-request-body-parsing-and-method-checks-in-the-elisp-servlets)
- ORG-007: [Use one class for the "entry selected" state](organization.md#org-007-use-one-class-for-the-entry-selected-state)
- ORG-008: [Remove duplicated content-page styling in server and client](organization.md#org-008-remove-duplicated-content-page-styling-in-server-and-client)
- ORG-009: [Remove the service worker cache fallback for API calls, which can never match](organization.md#org-009-remove-the-service-worker-cache-fallback-for-api-calls-which-can-never-match)
- ORG-010: [Remove CSS declarations that more specific rules always override](organization.md#org-010-remove-css-declarations-that-more-specific-rules-always-override)
- DOC-002: [Commentary endpoint list omits the required HTTP methods](docs-consistency.md#doc-002-commentary-endpoint-list-omits-the-required-http-methods)
- DOC-003: ["Loopback is always permitted" is false for the IPv6 loopback address](docs-consistency.md#doc-003-loopback-is-always-permitted-is-false-for-the-ipv6-loopback-address)
- DOC-004: [favicon.ico docstring names the wrong redirect target](docs-consistency.md#doc-004-faviconico-docstring-names-the-wrong-redirect-target)
- DOC-005: [README features and ideas don't match the shipped UI](docs-consistency.md#doc-005-readme-features-and-ideas-dont-match-the-shipped-ui)
- DOC-006: [README says `.gitattributes` keeps "the newer files"](docs-consistency.md#doc-006-readme-says-gitattributes-keeps-the-newer-files-mergeours-keeps-the-checked-out-side)
- DOC-007: [DISCOVERIES.md uses identifiers that no longer exist](docs-consistency.md#doc-007-discoveriesmd-uses-identifiers-that-no-longer-exist)
- DOC-008: [The dev proxy's hard-coded target is undocumented](docs-consistency.md#doc-008-the-dev-proxys-hard-coded-target-is-undocumented-and-conflicts-with-the-recommended-bind)
- DOC-009: [No documented way to run the tests](docs-consistency.md#doc-009-no-documented-way-to-run-the-tests-the-test-header-has-a-vague-placeholder)
- DOC-010: [Historical and current docs are mixed in `docs/` with no entry point](docs-consistency.md#doc-010-historical-and-current-docs-are-mixed-in-docs-with-no-entry-point)
- TST-006: [Test the JSON shape produced by elfeed-web-ng-for-json](testing.md#tst-006-test-the-json-shape-produced-by-elfeed-web-ng-for-json)
- TST-007: [Test the feed-update poll chain and the long-poll endpoint](testing.md#tst-007-test-the-feed-update-poll-chain-and-the-long-poll-endpoint)
- TST-008: [Test /elfeed/search with a missing or empty query](testing.md#tst-008-test-elfeedsearch-with-a-missing-or-empty-query)
- PKG-001: [Add an automated check that committed web/ matches src/](packaging.md#pkg-001-add-an-automated-check-that-committed-web-matches-src)
- PKG-002: [Emacs minimum version 29.2 looks higher than the code needs](packaging.md#pkg-002-emacs-minimum-version-292-looks-higher-than-the-code-needs)
- PKG-003: [Version string is hard-coded in three places](packaging.md#pkg-003-version-string-is-hard-coded-in-three-places)
- PKG-004: [package.json lacks license and package-manager pinning](packaging.md#pkg-004-packagejson-lacks-license-and-package-manager-pinning)
- PKG-005: [Elisp library header lacks Author/Maintainer and Keywords](packaging.md#pkg-005-elisp-library-header-lacks-authormaintainer-and-keywords)
- GEN-003: [Swiping an entry leaves the open reader's tag state stale](general.md#gen-003-swiping-an-entry-leaves-the-open-readers-tag-state-stale)
- GEN-004: [Clearing the selection via search leaves a dangling history entry](general.md#gen-004-clearing-the-selection-via-search-leaves-a-dangling-history-entry)
- GEN-005: [Tag changes made in the web UI are neither saved nor signalled to Emacs](general.md#gen-005-tag-changes-made-in-the-web-ui-are-neither-saved-nor-signalled-to-emacs)
- GEN-006: [`feed-update-done` can park a request with nothing to answer it](general.md#gen-006-feed-update-done-can-park-a-request-with-nothing-to-answer-it)
- GEN-007: [`/elfeed/things/<webid>` returns 500 for an unknown webid](general.md#gen-007-elfeedthingswebid-returns-500-for-an-unknown-webid)
- GEN-008: [The reader renders error bodies as entry content](general.md#gen-008-the-reader-renders-error-bodies-as-entry-content)

## Skipped

- Historical docs: `docs/2026-04-24-fixes.md` and `legacy/` were not checked for drift.
- Tests: the ERT suite ran and passed 9/9. There are no frontend tests, and no coverage tooling is configured.
- Spot-check: TST-001, the only high finding, was confirmed against the code: no test calls any servlet.
- The packaging agent ran `pnpm install --frozen-lockfile --lockfile-only` while checking the lockfile. No tracked file changed.
