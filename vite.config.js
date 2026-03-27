import { defineConfig } from 'vite';
import preact from '@preact/preset-vite';

export default defineConfig({
  plugins: [preact()],
  root: 'src',
  base: '/elfeed/',
  build: {
    outDir: '../web',
    emptyOutDir: true,
  },
  server: {
    proxy: {
      '/elfeed/api': 'http://localhost:8082',
      '/elfeed/things': 'http://localhost:8082',
      '/elfeed/content': 'http://localhost:8082',
      '/elfeed/search': 'http://localhost:8082',
      '/elfeed/tags': 'http://localhost:8082',
      '/elfeed/update': 'http://localhost:8082',
      '/elfeed/mark-all-read': 'http://localhost:8082',
      '/elfeed/saved-searches': 'http://localhost:8082',
      '/elfeed/annotation': 'http://localhost:8082',
    },
  },
});
