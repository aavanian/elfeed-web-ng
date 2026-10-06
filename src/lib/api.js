// SPDX-License-Identifier: AGPL-3.0-or-later

const BASE = '/elfeed';

// Optional features of this server, such as 'annotations'.
let features = [];

// Read the server's capabilities. Rejects when the backend cannot be reached
// or refuses the request, which the app reports as a connection error.
export async function init() {
  const res = await fetch(`${BASE}/api`);
  if (!res.ok) throw new Error(`Capabilities request failed: ${res.status}`);
  const capabilities = await res.json();
  features = capabilities.features ?? [];
  return capabilities;
}

export function hasFeature(name) {
  return features.includes(name);
}

export async function search(query) {
  const res = await fetch(`${BASE}/search?q=${encodeURIComponent(query)}`);
  if (!res.ok) throw new Error(`Search failed: ${res.status}`);
  return res.json();
}

export async function getContent(ref) {
  const res = await fetch(`${BASE}/content/${ref}`);
  if (!res.ok) throw new Error(`Content request failed: ${res.status}`);
  return res.text();
}

async function updateTags(add, remove, entries) {
  const res = await fetch(`${BASE}/tags`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ add, remove, entries }),
  });
  if (!res.ok) throw new Error(`Tag update failed: ${res.status}`);
  return res.json();
}

// Add TAG to ENTRY, or remove it when the entry has it. Resolves to a copy
// of the entry carrying the tags the server reports after the change.
export async function toggleTag(entry, tag) {
  const has = entry.tags?.includes(tag) ?? false;
  const result = await updateTags(has ? [] : [tag], has ? [tag] : [], [entry.webid]);
  return { ...entry, tags: result[entry.webid] };
}

export async function feedUpdateDone() {
  const res = await fetch(`${BASE}/feed-update-done`);
  if (!res.ok) throw new Error(`Feed update done poll failed: ${res.status}`);
}

export async function markAllRead() {
  const res = await fetch(`${BASE}/mark-all-read`, { method: 'POST' });
  if (!res.ok) throw new Error(`Mark all read failed: ${res.status}`);
}

export async function getSavedSearches() {
  const res = await fetch(`${BASE}/saved-searches`);
  if (!res.ok) return [];
  return res.json();
}

export async function feedUpdate() {
  const res = await fetch(`${BASE}/feed-update`, { method: 'POST' });
  if (!res.ok) throw new Error(`Feed update failed: ${res.status}`);
}

export async function setAnnotation(webid, text) {
  if (!hasFeature('annotations')) return null;
  const res = await fetch(`${BASE}/annotation/${webid}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ annotation: text }),
  });
  if (!res.ok) throw new Error(`Annotation update failed: ${res.status}`);
  return res.json();
}
