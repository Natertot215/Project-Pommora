// A URL property value is a bare URL string, or a markdown link `[alias](url)` once the user Renames
// it (gives it a custom title). Markdown-native + agent-legible, exactly like Obsidian's `[]()`. The
// alias ALWAYS wins at render — it overrides the property's Full URL / Title look. This is the one
// seam that parses/serializes that shape; Cell render + the cell Edit/Rename writes both go through it.

import {
  MD_LINK,
  escapeAlias,
  isValidLink,
  linkDomain,
  normalizeLinkUrl,
  unescapeAlias,
} from '@shared/links'
import type { PropertyValue } from '@shared/propertyValue'

export type LinkValue = { url: string; alias?: string }

/** Parse a stored URL value: `[alias](url)` → { url, alias }; a bare string → { url }. An empty
 *  alias (`[](url)`) collapses to no alias. The alias is unescaped (`\]` → `]`) — see escapeAlias. */
export function parseLink(raw: string): LinkValue {
  const s = raw.trim()
  const m = MD_LINK.exec(s)
  if (m) return { url: m[2], alias: unescapeAlias(m[1]).trim() || undefined }
  return { url: s }
}

/** Serialize back to the stored form: an alias → `[alias](url)`; none → the bare url. The alias is
 *  escaped so a title containing `]` / `\` can't break the shape (silent corruption otherwise). */
export function serializeLink(v: LinkValue): string {
  return v.alias ? `[${escapeAlias(v.alias)}](${v.url})` : v.url
}

/** The click target for a url value: the URL to open when filled, else null (→ open the editor to
 *  type one in). Shared by the card + table cell click handlers. */
export function urlClickTarget(value: string | undefined): string | null {
  if (!value) return null
  return parseLink(value).url || null
}

/** Commit an EDITED url — the raw text is the new URL; a rename-set alias on the current value rides
 *  along (so editing the URL never silently drops the title). `null` clears (empty), `undefined` =
 *  invalid, don't commit. Shared by the card + table cell editors. */
export function urlValueFromEdit(
  raw: string,
  current: string | undefined,
): PropertyValue | null | undefined {
  const trimmed = raw.trim()
  if (trimmed === '') return null
  if (!isValidLink(trimmed)) return undefined
  const alias = current ? parseLink(current).alias : undefined
  return { kind: 'url', value: serializeLink({ url: normalizeLinkUrl(trimmed), alias }) }
}

/** Commit a RENAMED url — the raw text is the new alias; the current URL is preserved. An empty alias
 *  drops back to the bare URL. Shared by the card + table rename surfaces. */
export function urlValueFromRename(alias: string, current: string): PropertyValue {
  return {
    kind: 'url',
    value: serializeLink({ url: parseLink(current).url, alias: alias.trim() || undefined }),
  }
}

/** The text to render for a URL value. An alias always wins. Otherwise the look is the property's:
 *  `link-title` shows the fetched page `title` (the caller resolves it out-of-band + hands it in),
 *  falling back to the bare domain while it's loading or if the fetch failed; `link-url` (the default)
 *  shows the full URL. Titles are display-only — sort/filter pass no title, so ordering stays stable. */
export function linkDisplayText(
  raw: string,
  display?: 'link-url' | 'link-title',
  title?: string,
): string {
  const { url, alias } = parseLink(raw)
  if (alias) return alias
  if (display === 'link-title') return title ?? linkDomain(url)
  return url
}
