// Construct detection — inline regexes + block detectors (cheap prefilter → per-line AST confirm).
// Render and active-token paths share these helpers so detection can't disagree across layers.
// Wikilinks reuse @shared/connections.pageLinkPattern (DRY). Inline matchers return a FRESH /g
// regex per call so callers never share lastIndex.
import { parse } from '../parser'

// The `d` (indices) flag is set so token assembly can read exact per-group offsets
// (match.indices[n]); `.test()`/`.exec()` behave identically with it.

/** `![[name]]` image embed. Group 1 = name. */
export const imageEmbedRegex = (): RegExp => /!\[\[([^\]\r\n]*)\]\]/gd
/** `[text](url)` markdown link. Group 1 = text, 2 = url. */
export const markdownLinkRegex = (): RegExp => /\[([^\]\r\n]+)\]\(([^)\r\n]+)\)/gd
/** `` `code` `` inline code. Group 1 = code. */
export const inlineCodeRegex = (): RegExp => /`([^`\n]+)`/gd
/** `$$…$$` block latex (multiline). Group 1 = formula. */
export const blockLatexRegex = (): RegExp => /(?<!\$)\$\$([\s\S]+?)\$\$/gd
/** `$…$` inline latex (gate the content with isInlineMathContent). Group 1 = formula. */
export const inlineLatexRegex = (): RegExp => /(?<!\$)\$(?!\$)([^$\n]+?)\$(?!\$)/gd

/** A blockquote line's full marker prefix (one or more `>`, each with an optional space; nesting
 *  kept). Shared by the render intent (hide span) and Enter-continuation. */
export const blockquotePrefixRe = /^[ \t]*(?:>[ \t]?)+/

/** The deepest list nesting (Tab cap + the render indent cap; spec §6.2). */
export const MAX_NESTING_LEVEL = 3

/** Source-indent → visual nesting level (`tabs + ⌊spaces/2⌋`, capped at MAX_NESTING_LEVEL). */
export function indentLevel(ws: string): number {
  let tabs = 0
  let spaces = 0
  for (const ch of ws) ch === '\t' ? tabs++ : spaces++
  return Math.min(MAX_NESTING_LEVEL, tabs + Math.floor(spaces / 2))
}

/** The single list-marker parser. Every layer (detect predicates, input transforms, render intent)
 *  reads markers through this — never its own regex. Offsets are line-relative (`markerStart` =
 *  indent end). A `box` is reported whenever a `[…]` follows the marker; `kind` is `checkbox` only
 *  when that box is non-empty on a `-`/`*`/`+` bullet (an ordered `1. [ ]` stays `ordered`). */
export interface ListMarker {
  kind: 'ordered' | 'bullet' | 'checkbox'
  /** The bullet glyph char (`-`/`*`/`+`/`•`); undefined for ordered. */
  bullet?: string
  /** Ordered digits, e.g. `"12"`. */
  digits?: string
  level: number
  markerStart: number
  /** End of the marker token (after `-`, after the `.`, or after the `]`), before the trailing space. */
  markerEnd: number
  /** First content char (after the required trailing space). */
  contentStart: number
  /** The `[…]` box, when present (any inner, incl empty). */
  box?: { start: number; end: number; inner: string }
  /** Checkbox only. */
  checked?: boolean
}

const LIST_MARKER_RE = /^([ \t]*)(?:(\d+)\.|([-*+•]))(?:[ \t]*(\[([ xX]?)\]))?([ \t]+)(.*)$/d

export function parseListMarker(line: string): ListMarker | null {
  const m = LIST_MARKER_RE.exec(line)
  const idx = m?.indices
  const ws = idx?.[6]
  if (!m || !idx || !ws) return null
  const indent = m[1]
  const markerStart = indent.length
  const level = indentLevel(indent)
  const contentStart = ws[1]
  const b = idx[4]
  const box = b ? { start: b[0], end: b[1], inner: m[5] ?? '' } : undefined
  const bullet = m[3]

  if (bullet !== undefined && box && box.inner !== '' && '-*+'.includes(bullet)) {
    return { kind: 'checkbox', bullet, level, markerStart, markerEnd: box.end, contentStart, box, checked: box.inner !== ' ' }
  }
  if (m[2] !== undefined) {
    return { kind: 'ordered', digits: m[2], level, markerStart, markerEnd: markerStart + m[2].length + 1, contentStart, box }
  }
  return { kind: 'bullet', bullet, level, markerStart, markerEnd: markerStart + (bullet?.length ?? 1), contentStart, box }
}

const dashBulletRegex = /^([ \t]*)([-*+•](?:[ \t]*\[[ xX]?\])?[ \t]+)(.*)$/
// A real task marker: bullet, optional space, a NON-empty `[ xX]` box, then content space.
// `[ ]`/`[x]`/`[X]` count; empty `[]` does not.
const taskMarkerRegex = /^[ \t]*[-*+][ \t]*\[[ xX]\][ \t]+/
const headingPrefilter = /^[ ]{0,3}#{1,6}([ \t]|$)/
const blockquotePrefilter = /^[ \t]*>[ \t]/

/** `---` / `***` / `___` rule. Per-line AST confirm → `---` is always HR (no setext). */
export function isThematicBreakLine(line: string): boolean {
  const t = line.trim()
  if (t.length < 3 || (t[0] !== '-' && t[0] !== '*' && t[0] !== '_')) return false
  return parse(line).children.some((n) => n.type === 'thematicBreak')
}

/** ATX heading (`#`–`######`): ≤3 leading spaces, then a space or EOL after the hashes. */
export function isHeadingLine(line: string): boolean {
  if (!headingPrefilter.test(line)) return false
  return parse(line).children.some((n) => n.type === 'heading')
}

/** `> ` blockquote — a bare `>` (no following space/tab) does not activate. */
export function isBlockquoteLine(line: string): boolean {
  if (!blockquotePrefilter.test(line)) return false
  return parse(line).children.some((n) => n.type === 'blockquote')
}

/** A `-`-marker bullet (the only marker that renders a • glyph), EXCLUDING task lines. */
export function isDashBulletLine(line: string): boolean {
  const m = dashBulletRegex.exec(line)
  if (m === null) return false
  const marker = m[2]
  return marker.startsWith('-') && !marker.includes('[')
}

/** An ordered list line (`1. `, `12. `…). Markers render literally (no glyph), just recoloured. */
export function isOrderedListLine(line: string): boolean {
  return /^[ \t]*\d+\.[ \t]+/.test(line)
}

/** Does the line's marker carry a real (non-empty inner) task checkbox? Empty `[]` excluded. */
export function hasCheckbox(line: string): boolean {
  return taskMarkerRegex.test(line)
}

/** Inline-math gate (spec §4.8): keeps prose / currency `$…$` from tokenizing as math. */
export function isInlineMathContent(content: string): boolean {
  if (/^[+-]?(\d{1,3}(?:,\d{3})*|\d+)(?:\.\d+)?$/.test(content)) return false // currency
  const mathyCount = (content.match(/[\\^_{}=+\-*/<>]/g) ?? []).length
  if (mathyCount === 0) return /^[A-Za-z]{1,3}$/.test(content)
  const tokens = content.split(/\s+/).filter(Boolean).length
  if (mathyCount >= 3) return tokens <= 120
  if (mathyCount === 2) return tokens <= 40
  return tokens <= 6
}
