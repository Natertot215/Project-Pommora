// Pure body scanner: extract `[[Title]]` page connections from Markdown, aggregating
// repeats to the same normalized title into `multiplicity`. `[[ ]]` is the only syntax;
// `![[ ]]` embeds and `{{ }}` are excluded (handled by the pattern). Mirrors Swift's
// ConnectionScanner — no deps, no I/O.

import { normalizeTitle, pageLinkPattern, type ScannedConnection } from '@shared/connections'

/** Scan a Markdown body for page connections, aggregating repeats by normalized title. */
export function scanConnections(body: string): ScannedConnection[] {
  const counts = new Map<string, number>()
  for (const m of body.matchAll(pageLinkPattern())) {
    const key = normalizeTitle(m[1])
    if (!key) continue
    counts.set(key, (counts.get(key) ?? 0) + 1)
  }
  return [...counts].map(([normalizedTitle, multiplicity]) => ({ normalizedTitle, multiplicity }))
}
