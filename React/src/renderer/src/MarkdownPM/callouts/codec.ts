// The callout codec — the ONE place the `::` ⇄ `> [!type]` mapping lives. `::` is an INPUT
// shorthand only; on disk a callout is the portable Obsidian form `> [!type]` (a blockquote
// variant) so it stays a real callout in other editors. Detection consumes the canonical form.

// The `::[type]` shorthand as a whole line prefix (up to the caret), e.g. `::` or `::warning`.
const SHORTHAND_RE = /^::([a-zA-Z]*)$/
// The canonical callout opener: a blockquote whose first content is `[!type]`.
const CALLOUT_RE = /^>[ \t]*\[!([a-zA-Z]+)\]/

const DEFAULT_TYPE = 'note'

/** Expand a `::[type]` shorthand prefix to the canonical `> [!type] ` opener (default `note`).
 *  Returns null if the prefix isn't a callout shorthand. */
export function expandShorthand(linePrefix: string): string | null {
  const m = SHORTHAND_RE.exec(linePrefix)
  if (m === null) return null
  return `> [!${m[1] || DEFAULT_TYPE}] `
}

/** The callout type if `line` is a canonical callout opener (`> [!type] …`), else null. */
export function parseCalloutType(line: string): string | null {
  const m = CALLOUT_RE.exec(line)
  return m === null ? null : m[1].toLowerCase()
}

/** Is this line a canonical callout opener? */
export function isCalloutLine(line: string): boolean {
  return CALLOUT_RE.test(line)
}
