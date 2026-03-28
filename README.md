# elfeed-web-ng

A modern web interface for [Elfeed](https://github.com/skeeto/elfeed), the Emacs RSS/Atom feed reader.

## Features

- Mobile-friendly PWA (installable on iOS/Android)
- Saved searches with quick-access buttons
- Tag management (read/unread, star, later, custom tags)
- Annotation support (requires [elfeed-curate](https://github.com/rnadler/elfeed-curate))
- Backward compatible with the original elfeed-web server (graceful degradation)
- Responsive desktop/mobile layout

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

**Note:** `elfeed-web-ng-stop` stops the underlying simple-httpd server, which is shared across all packages that use it (e.g., impatient-mode, skewer-mode). If you need to keep simple-httpd running for other packages, set `elfeed-web-ng-enabled` to `nil` instead.

## Development

The frontend is built with Preact + Vite. Pre-built files are in `web/` so users never need Node.js.

To develop the frontend:

```sh
pnpm install
pnpm run dev    # Vite dev server with HMR, proxying to Emacs backend
pnpm run build  # Production build to web/
```

## Credits

This project is a fork of the `web` sub-package from [elfeed-web](https://github.com/skeeto/elfeed) by Christopher Wellons, originally released under the [Unlicense](https://unlicense.org/) (public domain). The original frontend files are preserved in the `legacy/` directory for reference.

## License

Copyright (C) 2024-2026.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

See [LICENSE](LICENSE) for the full text.
