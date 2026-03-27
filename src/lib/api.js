// SPDX-License-Identifier: AGPL-3.0-or-later

const BASE = '/elfeed';

let capabilities = null;

export async function init() {
  try {
    const res = await fetch(`${BASE}/api`);
    if (res.ok) {
      capabilities = await res.json();
    } else {
      capabilities = { server: 'legacy', features: [] };
    }
  } catch {
    capabilities = { server: 'legacy', features: [] };
  }
  return capabilities;
}

export function getCapabilities() {
  return capabilities;
}

export function hasFeature(name) {
  return capabilities?.features?.includes(name) ?? false;
}

export async function search(query) {
  const res = await fetch(`${BASE}/search?q=${encodeURIComponent(query)}`);
  if (!res.ok) throw new Error(`Search failed: ${res.status}`);
  return res.json();
}

export async function getThing(webid) {
  const res = await fetch(`${BASE}/things/${webid}`);
  if (!res.ok) throw new Error(`Thing not found: ${res.status}`);
  return res.json();
}

export function getContentUrl(ref) {
  return `${BASE}/content/${ref}`;
}

export async function updateTags(add, remove, entries) {
  const res = await fetch(`${BASE}/tags`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ add, remove, entries }),
  });
  if (!res.ok) throw new Error(`Tag update failed: ${res.status}`);
  return res.json();
}

export async function pollUpdate(time) {
  const url = time != null
    ? `${BASE}/update?time=${time}`
    : `${BASE}/update`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Poll failed: ${res.status}`);
  return res.json();
}

export async function markAllRead() {
  const res = await fetch(`${BASE}/mark-all-read`);
  if (!res.ok) throw new Error(`Mark all read failed: ${res.status}`);
  return res.json();
}

export async function getSavedSearches() {
  if (!hasFeature('saved-searches')) return [];
  const res = await fetch(`${BASE}/saved-searches`);
  if (!res.ok) return [];
  return res.json();
}

export async function getAnnotation(webid) {
  if (!hasFeature('annotations')) return null;
  const res = await fetch(`${BASE}/annotation/${webid}`);
  if (!res.ok) return null;
  return res.json();
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
