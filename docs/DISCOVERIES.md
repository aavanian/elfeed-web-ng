# Discoveries

Lessons learned and non-obvious gotchas found during development.

## straight.el serves the build dir, and won't relink new filenames

The Emacs server resolves `elfeed-web-ng-data-root` from `load-file-name`, so it
serves static files from straight's **build dir**
(`straight/build-<emacs-version>/elfeed-web-ng/web`), not the repo. straight
populates that dir with **per-file symlinks** back into the repo.

Consequence: content-hashed asset filenames (e.g. `index-<hash>.js`) produce a
*new* filename on every build, and straight's incremental build does not
reliably create a symlink for it — the server then 404s the asset referenced by
the freshly built `index.html`.

Fix adopted: build with **stable filenames** (`assets/index.js` /
`assets/index.css`, see `vite.config.js`). The symlink set never changes, so
after one clean relink every `pnpm build` just overwrites the targets the
existing symlinks point at — no relinking needed again. Cache-busting moves to
the service worker.

## A manually-deleted straight build dir leaves a stale build-cache entry

If you `rm -rf` a package's build dir, `straight-rebuild-package` silently
no-ops: it trusts `straight/build-<emacs-version>-cache.el`, which still lists
the package as built, and skips re-symlinking without noticing the directory is
gone.

Fix: `M-x straight-prune-build-cache` drops cache entries whose build dirs no
longer exist, after which a rebuild (or restart) recreates the dir. Deleting the
whole cache file and restarting also works but re-validates every package.

## Service worker caches the app shell; installed PWAs serve stale builds

`web/sw.js` precaches the app shell (`/elfeed/`) cache-first under a fixed
`CACHE_NAME`, so an installed home-screen PWA keeps serving the old
`index.html` after a deploy. On iOS the home-screen app is its own sandboxed
container (and, if added via a third-party default browser, is not listed under
Safari's Website Data) — the reliable bust used to be to delete and re-add the
home-screen icon.

Fix adopted (#11): the `stampServiceWorker` Vite plugin replaces a
`__BUILD_ID__` placeholder in the emitted `sw.js` with `Date.now()` on every
build, so `CACHE_NAME` changes each build and the existing `activate` handler
evicts the stale shell. The app shell (navigations + static assets) is now
served **network-first** with the cache as offline fallback, so an online device
always pulls the fresh build on next launch — no manual cache clearing. Because
`sw.js` lives in the public dir (copied verbatim, never transformed by Vite),
the plugin rewrites the output file in `closeBundle` rather than via `transform`.

## Swapping an iframe's `srcdoc` pushes a phantom history entry

The entry reader mounted its content `<iframe>` immediately with `srcdoc=""`,
then set `srcdoc` to the fetched HTML once it arrived. That second assignment is
a *document navigation*, and the iframe's navigation lands on the shared session
history — so opening one entry pushed **two** entries (the app's `pushState` plus
the iframe's). The in-app Back then needed two taps: the first `history.back()`
unwound the iframe navigation (no parent `popstate`, so the entry stayed open),
only the second popped the app's state and dismissed the reader.

Fix: don't mount the iframe until `srcdoc` is ready (show a placeholder while
fetching), so it loads its final document exactly once. Verified via Playwright:
`history.length` now grows by exactly 1 per entry opened, and a single Back tap
returns to the list.
