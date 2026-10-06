import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { defineConfig } from 'vite';
import preact from '@preact/preset-vite';

// check.sh rebuilds with the stamps of the committed bundle, passed as JSON
// in ELFEED_BUILD_STAMPS, so that unchanged sources reproduce web/ byte for
// byte: the minifier picks identifier names from the whole output, stamps
// included, so they cannot be masked after the fact.
const stamps = process.env.ELFEED_BUILD_STAMPS
  ? JSON.parse(process.env.ELFEED_BUILD_STAMPS)
  : null;

const buildId = stamps?.buildId ?? Date.now().toString(36);

// Describe the checkout the bundle was built from. Failures are expected (a
// tarball install has no git), and the placeholder keeps the readout honest.
function gitInfo() {
  const git = (...args) => {
    try {
      return execFileSync('git', args, { encoding: 'utf8' }).trim();
    } catch {
      return '';
    }
  };
  return {
    describe: git('describe', '--tags', '--always', '--dirty') || 'unknown',
    branch: git('rev-parse', '--abbrev-ref', 'HEAD') || 'unknown',
    commit: git('rev-parse', '--short', 'HEAD') || 'unknown',
  };
}

// Stamp the build id into the emitted sw.js and stylesheet, replacing the
// __BUILD_ID__ placeholder. In sw.js it makes CACHE_NAME change on every build;
// in the stylesheet it exposes --build-id, so the app can report which CSS the
// browser actually loaded (a stale stylesheet behind a fresh bundle is
// otherwise invisible). Both are written after the bundle, since sw.js is a
// public-dir file copied verbatim.
function stampBuildId() {
  let root;
  let outDir;
  const stamp = (path) => {
    const src = readFileSync(path, 'utf8');
    writeFileSync(path, src.replace(/__BUILD_ID__/g, buildId));
  };
  return {
    name: 'stamp-build-id',
    apply: 'build',
    configResolved(config) {
      root = config.root;
      outDir = config.build.outDir;
    },
    closeBundle() {
      stamp(resolve(root, outDir, 'sw.js'));
      stamp(resolve(root, outDir, 'assets/index.css'));
    },
  };
}

export default defineConfig({
  plugins: [preact(), stampBuildId()],
  root: 'src',
  base: '/elfeed/',
  define: {
    __BUILD_INFO__: JSON.stringify(stamps ?? {
      ...gitInfo(),
      buildId,
      date: new Date().toISOString(),
    }),
  },
  build: {
    outDir: '../web',
    emptyOutDir: true,
    // Stable, non-hashed filenames so the straight build dir's symlinks stay
    // valid across builds (no relinking needed). Cache-busting is handled by
    // the service worker, not by filename hashing.
    rollupOptions: {
      output: {
        entryFileNames: 'assets/index.js',
        chunkFileNames: 'assets/[name].js',
        assetFileNames: 'assets/index[extname]',
      },
    },
  },
  server: {
    proxy: {
      '/elfeed/api': 'http://localhost:8082',
      '/elfeed/things': 'http://localhost:8082',
      '/elfeed/content': 'http://localhost:8082',
      '/elfeed/search': 'http://localhost:8082',
      '/elfeed/tags': 'http://localhost:8082',
      '/elfeed/feed-update': 'http://localhost:8082',
      '/elfeed/feed-update-done': 'http://localhost:8082',
      '/elfeed/mark-all-read': 'http://localhost:8082',
      '/elfeed/saved-searches': 'http://localhost:8082',
      '/elfeed/annotation': 'http://localhost:8082',
    },
  },
});
