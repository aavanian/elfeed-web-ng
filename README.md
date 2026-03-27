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
(require 'elfeed-web-ng)

(setq elfeed-web-ng-saved-searches
  '((:label "Unread"    :filter "+unread")
    (:label "Starred"   :filter "+★")
    (:label "Later"     :filter "+later +unread")))

(elfeed-web-ng-start)
```

### Configuration

- `elfeed-web-ng-saved-searches` — list of saved searches displayed as quick-access buttons
- `elfeed-web-ng-limit` — maximum entries per search (default: 512)
- `httpd-host` / `httpd-port` — server binding (from simple-httpd)

## Development

The frontend is built with Preact + Vite. Pre-built files are in `web/` so users never need Node.js.

To develop the frontend:

```sh
npm install
npm run dev    # Vite dev server with HMR, proxying to Emacs backend
npm run build  # Production build to web/
```

## Credits

This project is a fork of the `web` sub-package from [elfeed-web](https://github.com/skeeto/elfeed) by Christopher Wellons, originally released under the [Unlicense](https://unlicense.org/) (public domain). The original frontend files are preserved in the `legacy/` directory for reference.

## License

Copyright (C) 2024-2026.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

See [LICENSE](LICENSE) for the full text.
