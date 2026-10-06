# elfeed-web-ng

A modern web interface for [Elfeed](https://github.com/skeeto/elfeed), the Emacs RSS/Atom feed reader.

## Features

- Mobile-friendly PWA (installable on iOS/Android)
- Saved searches with quick-access buttons
- Tag management (read/unread, star, later, custom tags)
- Annotation support (requires [elfeed-curate](https://github.com/rnadler/elfeed-curate))
- Responsive desktop/mobile layout

## Compatibility

This interface requires the `elfeed-web-ng` Emacs backend; it is **no longer a
drop-in replacement for the upstream [elfeed-web](https://github.com/skeeto/elfeed)
server**. The "Update feeds" button drives an `elfeed-web-ng`-only feed-update
endpoint that triggers `elfeed-update` server-side, which upstream elfeed-web
does not provide.

The last commit that still degraded gracefully against a stock elfeed-web
backend is tagged [`legacy-compat`](https://github.com/aavanian/elfeed-web-ng/releases/tag/legacy-compat).
Check out that tag if you need to run the UI against upstream elfeed-web.

## Installation

Add `elfeed-web-ng` to your `load-path` and configure:

```elisp
(use-package elfeed-web-ng
  :after elfeed
  :straight (:type git :host github :repo "aavanian/elfeed-web-ng" :files ("*.el" "web"))
  :init
  ;; you don't need this if you already install simple-httpd elsewhere
  (use-package simple-httpd
    :straight (simple-httpd :type git :host github :repo "skeeto/emacs-web-server"
                            :local-repo "skeeto-emacs-web-server")
    :config
    (setq httpd-host "127.0.0.1"
          httpd-port 8082))
  :custom
  (elfeed-web-ng-saved-searches
   '((:label "Unread"    :filter "+unread -later -to_source")
     (:label "Starred"   :filter "+★")
     (:label "Annotated" :filter "+⮐")
     (:label "Later"     :filter "+later +unread"))))
```

### Notes

* there are (at least) two simple-httpd servers available through straight with conflicting name, hence the detailed recipe above.
* the example above listens to "127.0.0.1" which is restrictive. Obviously, listening to "0.0.0.0" would be dangerous. My pattern is to use tailscale:

```elisp
(defvar 151e/my-tailscale-ip
  (let ((ip (string-trim (shell-command-to-string "tailscale ip -4"))))
    (if (string-match-p "^100\\." ip)
        ip
      "127.0.0.1")))
```
  
  so and binding the server to that variable. Then I can access the interface safely from my mobile device with a home-screen bookmark to "http://machine-name.tailnet-name.ts.net:8082/elfeed" 

### Configuration

- `elfeed-web-ng-saved-searches` — list of saved searches displayed as quick-access buttons
- `elfeed-web-ng-limit` — maximum entries per search (default: 512)
- `httpd-host` / `httpd-port` — server binding (from simple-httpd)
- `elfeed-web-ng-allowed-hosts` — hostnames permitted in the `Host`/`Origin` headers (default: derived)
- `elfeed-web-ng-allow-public-bind` — silence the all-interfaces bind warning (default: `nil`)

**Note:** `elfeed-web-ng-stop` stops the underlying simple-httpd server, which is shared across all packages that use it (e.g., impatient-mode, skewer-mode). If you need to keep simple-httpd running for other packages, set `elfeed-web-ng-enabled` to `nil` instead.

**Note:** tag changes made in the web interface, such as marking entries read,
show up at once in an open `*elfeed-search*` buffer, but, as with changes made in
Emacs, they reach disk only when Elfeed saves its database (on exit, or when the
search buffer is quit). To save them sooner, for example after a few idle
minutes:

```elisp
(defvar my/elfeed-save-timer nil)
(defun my/elfeed-save-soon (&rest _)
  (when my/elfeed-save-timer (cancel-timer my/elfeed-save-timer))
  (setq my/elfeed-save-timer (run-with-idle-timer 180 nil #'elfeed-db-save)))
(add-hook 'elfeed-tag-hook #'my/elfeed-save-soon)
(add-hook 'elfeed-untag-hook #'my/elfeed-save-soon)
```

Before Elfeed 4.0 the hooks are named `elfeed-tag-hooks` and `elfeed-untag-hooks`.

### Security

This interface has **no authentication** — it assumes it is served on a private
interface (loopback or a single-user tailnet). Two safeguards reduce the ways to
get this wrong; neither is a substitute for keeping the bind address private.

**Host allowlist and same-origin check.** Requests whose `Host` header names a
host outside `elfeed-web-ng-allowed-hosts` are rejected (blocking DNS-rebinding).
A request that carries an `Origin` header must come from the same host and port
it was sent to, so no other site, including another web service on the same
machine such as a dev server on `localhost:3000`, can drive the API (blocking
CSRF). When `elfeed-web-ng-allowed-hosts` is `nil` (the default) the allowlist is
derived from `httpd-host` plus the loopback names (`localhost`, `127.0.0.1`,
`[::1]`), so the common single-bind-address setup needs no configuration.
If you reach the interface under more than one name (for example the raw tailnet
IP *and* a Tailscale MagicDNS name), list every hostname you use:

```elisp
(setq elfeed-web-ng-allowed-hosts
      '("100.64.0.1" "machine-name.tailnet-name.ts.net"))
```

A rejected request returns a generic `403`; the host it was addressed to is
recorded in the `*httpd*` log, next to the request entry that shows the client
address, so you can see exactly what to add.

**What the safeguards cover.** They apply to the `/elfeed/` paths only. The
simple-httpd server is shared, so everything else it serves on the same address
lacks them: other packages' servlets (such as impatient-mode or skewer), and,
because simple-httpd defaults to `httpd-serve-files` `t`, the files and
directory listings under `httpd-root` (`~/public_html` by default). Unless you
use simple-httpd to serve files, turn that off:

```elisp
(setq httpd-serve-files nil)
```

**All-interfaces bind warning.** If `httpd-host` is unset or a wildcard
(`0.0.0.0` / `::`) when you start the server, a warning fires, since the
unauthenticated interface is then exposed on every network the machine joins.
Pin `httpd-host` to a private address, or set `elfeed-web-ng-allow-public-bind`
to acknowledge a deliberate public bind (e.g. behind an authenticating reverse
proxy).

## Development

The frontend is built with Preact + Vite. Pre-built files are in `web/` so users never need Node.js.

To develop the frontend:

```sh
pnpm install
pnpm run dev    # Vite dev server with HMR, proxying to Emacs backend
pnpm run build  # Production build to web/
```

### Tests

`./check.sh` runs every automated check and exits non-zero on the first
failure: shellcheck, byte-compilation, the ERT suite, the frontend tests, and a
rebuild of the frontend that must match the committed `web/`. It needs
`pnpm install` to have run, and the elisp dependencies, elfeed and simple-httpd. By default it
takes them from the straight.el build directory next to this checkout
(`../../build-<emacs-version>/`). Point it elsewhere with:

```sh
ELFEED_DIR=/path/to/elfeed HTTPD_DIR=/path/to/simple-httpd ./check.sh
```

To run only the frontend tests (Node's built-in test runner), use `pnpm test`.
To run only the ERT suite:

```sh
emacs --batch -L "$ELFEED_DIR" -L "$HTTPD_DIR" -L . \
      -l test/elfeed-web-ng-test.el -f ert-run-tests-batch-and-exit
```

### Merging / Rebasing

Since the built files are under version control, most merge or rebase will lead to conflict on those. The `.gitattributes` file is set to ignore the conflict and take the newer files in any case. They will be stale and will need a rebuild which should then be committed (ideally squashing that build commit with the merge commit if any or one of the merged/rebased commits. You will need something like `git config --global merge.ours.driver true` in your config for the `.gitattributes` config to work.

## Ideas

- **Keyboard navigation** — arrow keys to move between entries, enter to open, escape to go back
- **Offline support** — cache app shell and pre-load entry content so the page works without network, syncing tag changes when back online

## Credits

This project is a fork of the `web` sub-package from [elfeed-web](https://github.com/skeeto/elfeed) by Christopher Wellons, originally released under the [Unlicense](https://unlicense.org/) (public domain). The original frontend files are preserved in the `legacy/` directory for reference.

## License

Copyright (C) 2024-2026.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

See [LICENSE](LICENSE) for the full text.
