// SPDX-License-Identifier: AGPL-3.0-or-later

// Format an entry timestamp (milliseconds) for display. The list shows a
// compact day/month; the reader pane includes the year via { withYear: true }.
export function formatDate(ms, { withYear = false } = {}) {
  return new Date(ms).toLocaleDateString(undefined, {
    ...(withYear ? { year: 'numeric' } : {}),
    month: 'short',
    day: 'numeric',
  });
}
