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
Safari's Website Data) — the reliable bust is to delete and re-add the
home-screen icon. Tracked for a proper fix (build-time cache versioning +
network-first shell) in issue #11.
