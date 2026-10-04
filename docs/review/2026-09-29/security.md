# Security review: elfeed-web-ng

Scope: whole repository · Commit: 0e482e5 · Date: 2026-09-29

This review found no critical, high or medium issues. The main defenses hold up when checked against the code and the simple-httpd source:
- Path traversal is blocked: `httpd-clean-path` removes `..` after decoding.
- Content refs and webids are validated.
- State-changing endpoints require POST or PUT.
- Feed HTML is rendered only in a script-less sandbox: `sandbox="allow-popups"`, a CSP sandbox header on `/content/`, and no `dangerouslySetInnerHTML`.
- The service worker caches only static paths.

Also checked: no hardcoded secrets, no text addressed to an AI, locked dependencies are current (vite 5.4.21), and `legacy/` is never served (the data root is `web/`). What remains is five low-severity findings.

## SEC-001: Origin check ignores port and always admits loopback (CSRF)

- **Severity:** low
- **Confidence:** high
- **Location:** `elfeed-web-ng.el:218-228`, `elfeed-web-ng.el:235-245`, `elfeed-web-ng.el:355-363`, `elfeed-web-ng.el:475-489`, `test/elfeed-web-ng-test.el:74-77`
- **Labels:** security, csrf, backend

`elfeed-web-ng--origin-allowed-p` compares only `url-host` against the allowlist. It ignores scheme and port, and a test asserts exactly that (test:74-77). `--effective-allowed-hosts` always adds `localhost`, `127.0.0.1` and `::1`, even when the server is bound to a tailnet IP. So a page from another local origin such as `http://localhost:3000` passes the check. It can then send a simple cross-site `POST` to `/elfeed/mark-all-read` or `/elfeed/feed-update`, which needs no preflight. The PUT endpoints are still protected by CORS preflight.

**Why it matters:** untrusted HTML shown by any other local web service (a dev server, an HTML preview, a notebook) can clear unread state across the whole database, and that cannot be undone.

**Suggested fix:** compare the full origin: require the Origin to equal `http(s)://` plus the request's own Host, or keep port-qualified allowlist entries. Stop adding loopback names when `httpd-host` is not a loopback address.

**Done when:** an Origin of `http://localhost:3000` gets 403 against servers on both `127.0.0.1:8082` and a tailnet IP, same-origin requests still pass, and ERT tests cover both cases.

## SEC-002: Paths outside /elfeed/ bypass the Host/Origin allowlist

- **Severity:** low
- **Confidence:** medium
- **Location:** `elfeed-web-ng.el:519-523`, `elfeed-web-ng.el:540-542`, `elfeed-web-ng.el:563-568`
- **Labels:** security, insecure-default, backend

`elfeed-web-ng-start` calls `httpd-start` on the shared simple-httpd server without changing its defaults. Those defaults are `httpd-serve-files t`, `httpd-root "~/public_html"` and `httpd-listings t` (simple-httpd.el:127-137). Any unmatched path falls through to the root servlet, which serves that directory with listings (simple-httpd.el:817-830). The allowlist is applied only inside the `elfeed/*` servlets. The same gap covers servlets from other packages on the same server, such as impatient-mode or skewer. With a tailnet bind, all of this is exposed on that address and reachable by DNS rebinding.

**Why it matters:** whether this applies depends on setup. If `~/public_html` exists or another httpd package is loaded, its content lacks the DNS-rebinding protection the README describes.

**Suggested fix:** document that the allowlist covers only `/elfeed/`. Then either register a Host/Origin check for every request through `httpd-filter-functions`, or recommend `httpd-serve-files nil` in the README snippet.

**Done when:** a request to `/` with a disallowed Host gets 403, or the README disables `httpd-serve-files` and states what the allowlist covers.

## SEC-003: Remote subresources in entry content leak the server address via Referer

- **Severity:** low
- **Confidence:** medium
- **Location:** `src/components/EntryContent.jsx:10-23`, `src/components/EntryContent.jsx:126-131`, `web/index.html:1-25`
- **Labels:** security, privacy, frontend

Feed HTML is loaded into an `about:srcdoc` iframe, so its remote `<img>`, `<video>` and `<iframe>` requests use the parent page as their referrer source. No referrer policy is set: `CONTENT_STYLE` has no meta tag, `index.html` has none, and the server sends no `Referrer-Policy` header. Under the default `strict-origin-when-cross-origin`, every image host receives `Referer: http://<tailnet-ip or MagicDNS name>:<port>/`. Links already use `rel="noopener noreferrer"`, but subresources do not.

**Why it matters:** every image host and tracking pixel learns the reader's private hostname and port, and a MagicDNS name identifies the user's tailnet.

**Suggested fix:** add `<meta name="referrer" content="no-referrer">` to `CONTENT_STYLE`. Optionally also send `Referrer-Policy: no-referrer` for `index.html` and `/content/`.

**Done when:** opening an entry with a remote image sends no Referer, checked in the devtools network panel.

## SEC-004: JSON request bodies are not validated (symbol interning, types, size)

- **Severity:** low
- **Confidence:** high
- **Location:** `elfeed-web-ng.el:181-187`, `elfeed-web-ng.el:376-383`, `elfeed-web-ng.el:444-450`
- **Labels:** security, input-validation, backend

- **Interning:** `elfeed-web-ng--valid-tag-p` exists to prevent "unbounded obarray growth via `intern`". But `json-read-from-string` with the default `json-object-type 'alist` already interns every object key (`json-add-to-object`: `(intern key)`). Any PUT body therefore interns arbitrary symbols before tags are checked.
- **Types:** `annotation` is not type-checked. A number makes `elfeed-curate-set-entry-annotation` signal an error. An array or object is stored in the entry's meta as a Lisp vector or alist.
- **Size:** request bodies have no size limit (simple-httpd.el:431-437).

**Why it matters:** any client that passes the Host check can permanently bloat the Emacs process or store malformed annotations in the persistent database.

**Suggested fix:** parse with `json-key-type 'string`, or with `json-parse-string` using string keys. Require `annotation` to be a bounded-length string, and reject oversized bodies.

**Done when:** a body with 10k distinct keys adds no symbols to the obarray, `{"annotation": 5}` and `{"annotation": [1]}` return 400, and ERT tests cover both.

See also: TST-002, ORG-006.

## SEC-005: Search result limit can be overridden from the query string

- **Severity:** low
- **Confidence:** high
- **Location:** `elfeed-web-ng.el:52-55`, `elfeed-web-ng.el:331-345`
- **Labels:** security, input-validation, backend

The servlet builds `(format "#%d %s" elfeed-web-ng-limit q)` (:335). `elfeed-search-parse-filter` handles each `#N` with `(setf limit ...)` (elfeed-search.el:554), so the last one wins. So `q=#100000000` lifts the cap, and the whole database is serialized synchronously in the single-threaded Emacs process. Also, when `q` is absent the filter becomes `"#512 nil"`, which filters on the regexp "nil".

**Why it matters:** the configured cap (default 512) does not hold, so one request can freeze Emacs for as long as the full serialization takes.

**Suggested fix:** clamp after parsing with `(plist-put filter :limit (min (or (plist-get filter :limit) elfeed-web-ng-limit) elfeed-web-ng-limit))`, and treat a missing `q` as "".

**Done when:** `/elfeed/search?q=%23100000` returns at most `elfeed-web-ng-limit` entries, and an ERT test covers it.

See also: TST-008.
