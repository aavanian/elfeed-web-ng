# Discoveries

Lessons learned and non-obvious gotchas found during development.

## straight.el serves the build dir, and won't relink new filenames

The Emacs server resolves `elfeed-web-ng--data-root` from `load-file-name`, so it
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

Fix adopted (#11): the `stampBuildId` Vite plugin (`'stamp-build-id'` in
`vite.config.js`) replaces a `__BUILD_ID__` placeholder with
`Date.now().toString(36)` on every build, in the emitted `sw.js` and in
`assets/index.css`. In `sw.js` it makes `CACHE_NAME` change each build, so the
existing `activate` handler evicts the stale shell; in the stylesheet it sets
`--build-id`, which the build info panel compares with the script's own build id
to reveal a stale stylesheet. The app shell (navigations + static assets) is now
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

## The minifier renames identifiers when any embedded string changes

The bundle embeds build stamps (git describe, commit, build id, date). esbuild
picks short identifier names from character frequencies across the whole
output, so a different commit hash renames variables throughout
`assets/index.js`, not just the stamp. Masking the stamps after the build
therefore cannot tell "same sources" from "different sources".

Fix adopted: `check.sh` reads the stamps back from the committed bundle and
rebuilds with them (`ELFEED_BUILD_STAMPS`), so unchanged sources reproduce
`web/` byte for byte.

## WebKit sends a Referer from an about:srcdoc frame

The reader shows feed HTML in a sandboxed `about:srcdoc` iframe. With no referrer
policy, WebKit (the engine of the iOS home-screen app) sent the app's address,
`http://<host>:<port>/`, as Referer for every remote image in it; Chromium sent
none. Checked with Playwright by intercepting the image requests.

Fix adopted: `<meta name="referrer" content="no-referrer">` in the frame's
document, plus a `Referrer-Policy: no-referrer` header on the app shell, whose
policy srcdoc frames inherit.

## Vite's proxy shorthand rewrites Host but not Origin

`'/path': 'http://backend'` in `server.proxy` sends the backend's address as
`Host` but forwards the browser's `Origin` unchanged. A backend that requires
the Origin to name itself then refuses every PUT and POST from the dev server.

Fix adopted: the proxy entries set `changeOrigin` and an explicit `origin`
header equal to the backend's own origin.

## Emacs 31 ignores a let-bound `features` in `featurep`

`(let ((features (cons 'x features))) (featurep 'x))` returns nil in Emacs 31,
so a test cannot pretend an optional package such as elfeed-curate is loaded
that way. The tests `provide` the feature inside `unwind-protect` and remove it
from `features` afterwards.
