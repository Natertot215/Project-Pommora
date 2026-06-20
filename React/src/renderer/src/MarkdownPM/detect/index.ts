// Construct detection — the verbatim regexes from the spec (§4.1) + the three-stage block
// detectors (cheap prefilter → per-line AST confirm). Both the render and active-token paths
// share these helpers, so detection can never disagree across layers. Wikilink detection is
// NOT redefined here — it reuses @shared/connections.pageLinkPattern (DRY with the scanner /
// resolver / rewrite). Inline matchers return a FRESH /g regex per call (like pageLinkPattern)
// so callers never share lastIndex.
import { parse } from '../parser'

/** `![[name]]` image embed. Group 1 = name. */
export const imageEmbedRegex = (): RegExp => /!\[\[([^\]\r\n]*)\]\]/g
/** `[text](url)` markdown link. Group 1 = text, 2 = url. */
export const markdownLinkRegex = (): RegExp => /\[([^\]\r\n]+)\]\(([^)\r\n]+)\)/g
/** `` `code` `` inline code. Group 1 = code. */
export const inlineCodeRegex = (): RegExp => /`([^`\n]+)`/g
/** `$$…$$` block latex (multiline). Group 1 = formula. */
export const blockLatexRegex = (): RegExp => /(?<!\$)\$\$([\s\S]+?)\$\$/g
/** `$…$` inline latex (gate the content with isInlineMathContent). Group 1 = formula. */
export const inlineLatexRegex = (): RegExp => /(?<!\$)\$(?!\$)([^$\n]+?)\$(?!\$)/g

/** A list line: bullet (`-*+•`) or ordered (`\d+.`), with an optional task bracket. Group 1 =
 *  whole marker run, group 2 = ordered digits. The optional `[…]?` is deliberate — a bare
 *  `-[]` still reads as a list LINE (it indents/continues); only checkbox rendering excludes
 *  empty `[]`. (Non-global; fresh per call for symmetry.) */
export const listRegex = (): RegExp => /^\s*((?:(\d+)\.|[-*+•])(?:\s*\[[ xX]?\])?\s+)/

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
