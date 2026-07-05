// Connection model. Connections live ONLY as title-only `[[Title]]` text in a Page's
// Markdown body (page→page) — no on-disk store, no frontmatter mirror, no id / pipe /
// alias. Resolution is computed at read time: normalized body-title → the unique page
// holding that title → its id; the id never touches disk. `![[ ]]` and `{{ }}` are not
// connections. Obsidian/GitHub-compatible. Mirrors Swift's ConnectionTitle/Scanner.
//
// This module is shared (renderer-importable: autocomplete + inline styling later) — no
// fs, no React. normalizeTitle is the SINGLE normalization the scanner, the phantom key,
// resolution, and uniqueness all share, so they can never disagree.

/** Trim + case-fold — the one normalization for connection titles. */
export function normalizeTitle(raw: string): string {
  return raw.trim().toLowerCase()
}

/** A fresh global regex matching `[[Title]]` / `[[Title|legacy]]` (pipe segment dropped),
 *  excluding `![[ ]]` image embeds. `[[ ]]` is the only connection syntax. Returned fresh
 *  per call so callers never share `lastIndex`. Capture group 1 = the raw title. */
export function pageLinkPattern(): RegExp {
  return /(?<!!)\[\[([^[\]\r\n|]+)(?:\|[^\]\r\n]*)?\]\]/g
}

/** A `[[Title]]` occurrence found in a body, aggregated by normalized title. */
export interface ScannedConnection {
  normalizedTitle: string
  multiplicity: number
}

/** Resolution outcome for a scanned title against the nexus link index. */
export type LinkStatus = 'resolved' | 'phantom' | 'ambiguous'

/** A resolved connection edge from a source page to a (possibly missing) target. */
export interface ConnectionEdge {
  sourceId: string
  normalizedTitle: string
  status: LinkStatus
  targetId?: string
  multiplicity: number
}

/** Nexus-wide resolution index: normalized page title → ids of pages holding it.
 *  Exactly one ⇒ resolved; more than one ⇒ ambiguous; absent ⇒ phantom. */
export type LinkIndex = Map<string, string[]>
