// SPDX-License-Identifier: AGPL-3.0-or-later

import '@picocss/pico/css/pico.min.css';
import { render } from 'preact';
import { App } from './app';

render(<App />, document.getElementById('app'));

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/elfeed/sw.js').catch(() => {});
}
