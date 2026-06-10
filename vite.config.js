import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { defineConfig } from 'vite';
import preact from '@preact/preset-vite';

// Stamp a unique build id into the emitted sw.js, replacing the __BUILD_ID__
// placeholder so CACHE_NAME changes on every build. sw.js lives in the public
// dir (copied verbatim, never transformed), so we rewrite the output file
// after the bundle has been written.
function stampServiceWorker() {
  let root;
  let outDir;
  return {
    name: 'stamp-service-worker',
    apply: 'build',
    configResolved(config) {
      root = config.root;
      outDir = config.build.outDir;
    },
    closeBundle() {
      const buildId = Date.now().toString(36);
      const swPath = resolve(root, outDir, 'sw.js');
      const src = readFileSync(swPath, 'utf8');
      writeFileSync(swPath, src.replace(/__BUILD_ID__/g, buildId));
    },
  };
}

export default defineConfig({
  plugins: [preact(), stampServiceWorker()],
  root: 'src',
  base: '/elfeed/',
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
