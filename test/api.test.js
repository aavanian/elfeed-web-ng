// SPDX-License-Identifier: AGPL-3.0-or-later

import { test, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import * as api from '../src/lib/api.js';

const realFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = realFetch; });

function respondWith(status, body) {
  globalThis.fetch = async () => ({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  });
}

test('init records the features the server advertises', async () => {
  respondWith(200, { server: 'elfeed-web-ng', version: '1.0.0', features: ['annotations'] });
  const caps = await api.init();
  assert.equal(caps.server, 'elfeed-web-ng');
  assert.equal(api.hasFeature('annotations'), true);
  assert.equal(api.hasFeature('other'), false);
});

test('init treats a missing feature list as no features', async () => {
  respondWith(200, { server: 'elfeed-web-ng', version: '1.0.0' });
  await api.init();
  assert.equal(api.hasFeature('annotations'), false);
});

test('init fails when the server answers with an error', async () => {
  respondWith(403, { error: 403 });
  await assert.rejects(api.init());
});

test('init fails when the server cannot be reached', async () => {
  globalThis.fetch = async () => { throw new TypeError('Failed to fetch'); };
  await assert.rejects(api.init());
});

test('getContent returns the content of a found entry', async () => {
  globalThis.fetch = async (url) => ({
    ok: true, status: 200, text: async () => `<p>${url}</p>`,
  });
  assert.equal(await api.getContent('abc'), '<p>/elfeed/content/abc</p>');
});

test('getContent fails rather than return an error page as content', async () => {
  globalThis.fetch = async () => ({
    ok: false, status: 404, text: async () => '{"error":404}',
  });
  await assert.rejects(api.getContent('abc'));
});

// Answer tag updates like the server: apply them and return each entry's tags.
function tagServer(initial) {
  const sent = [];
  globalThis.fetch = async (url, options) => {
    const body = JSON.parse(options.body);
    sent.push({ url, method: options.method, body });
    const tags = initial.filter((t) => !body.remove.includes(t)).concat(body.add);
    return { ok: true, status: 200, json: async () => ({ [body.entries[0]]: tags }) };
  };
  return sent;
}

test('toggleTag removes a tag the entry has', async () => {
  const sent = tagServer(['unread', 'later']);
  const entry = { webid: 'w1', title: 'T', tags: ['unread', 'later'] };
  const updated = await api.toggleTag(entry, 'unread');
  assert.deepEqual(sent, [{ url: '/elfeed/tags', method: 'PUT',
    body: { add: [], remove: ['unread'], entries: ['w1'] } }]);
  assert.deepEqual(updated, { webid: 'w1', title: 'T', tags: ['later'] });
});

test('toggleTag adds a tag the entry lacks', async () => {
  tagServer([]);
  const updated = await api.toggleTag({ webid: 'w1' }, '★');
  assert.deepEqual(updated.tags, ['★']);
});

test('toggleTag fails when the server refuses', async () => {
  globalThis.fetch = async () => ({ ok: false, status: 400 });
  await assert.rejects(api.toggleTag({ webid: 'w1', tags: [] }, 'later'));
});
