// Inline matchers return a fresh /g regex per call so callers never share lastIndex.
import { parse } from '../parser'

export const imageEmbedRegex = (): RegExp => /!\[\[([^\]\r\n]*)\]\]/dg
export const markdownLinkRegex = (): RegExp => /\[([^\]\r\n]+)\]\(([^)\r\n]+)\)/dg
export const inlineCodeRegex = (): RegExp => /`([^`\n]+)`/dg
export const blockLatexRegex = (): RegExp => /(?<!\$)\$\$([\s\S]+?)\$\$/dg
export const inlineLatexRegex = (): RegExp => /(?<!\$)\$(?!\$)([^$\n]+?)\$(?!\$)/dg

export const blockquotePrefixRe = /^[ \t]*(?:>[ \t]?)+/

/** Strip ONE `>` level (with its optional single space), preserving leading indent. The single source for
 *  un-quoting a line — a deeper `> > …` keeps its inner `>`. */
const oneQuoteLevelRe = /^([ \t]*)>[ \t]?/
export function stripQuotePrefix(line: string): string {
  return line.replace(oneQuoteLevelRe, '$1')
}

/** A line's quote depth: how many `>` levels it's nested under, ignoring list indent. */
export const quoteDepth = (line: string): number =>
  /^[ \t]*(?:>[ \t]?)*/.exec(line)?.[0].match(/>/g)?.length ?? 0

// A callout HEAD tags a type: `> [!callout] …`. The tag is the discriminator vs a plain quote and is invisible
// chrome (hidden at render) — `||` is the typing shorthand. Detection is per-HEAD, not per-run: any `[!type]`
// line starts its own callout, so adjacent / hand-typed / pasted heads never merge into one box with a raw tag.
const calloutTagRe = /^\[!([a-zA-Z][\w-]*)\][ \t]?/

export function isCalloutHead(line: string): boolean {
  return calloutHeadPrefixLen(line) !== null
}

export interface CalloutLine {
  first: boolean
  last: boolean
  /** Chars to hide at line start: the head line hides `> [!type] `, body lines hide their `> ` prefix. */
  prefixEnd: number
}

/** Per-line callout membership for the whole doc. A callout starts at each `[!type]` head and extends through
 *  the following blockquote lines that aren't themselves heads (a new head, or a non-quote line, ends it). */
export function calloutLines(lines: string[]): (CalloutLine | undefined)[] {
  const out: (CalloutLine | undefined)[] = new Array(lines.length)
  let i = 0
  while (i < lines.length) {
    if (!isCalloutHead(lines[i])) {
      i++
      continue
    }
    let j = i + 1
    while (j < lines.length && isBlockquoteLine(lines[j]) && !isCalloutHead(lines[j])) j++
    const headPrefix = blockquotePrefixRe.exec(lines[i])?.[0] ?? ''
    const tag = calloutTagRe.exec(lines[i].slice(headPrefix.length))
    for (let k = i; k < j; k++) {
      // Body lines strip only ONE `>` level (not the greedy prefix), so a deeper `> > …` keeps its inner `>`
      // for the nested-quote renderer. The head also hides its `[!type]` tag.
      const oneLevel = oneQuoteLevelRe.exec(lines[k])?.[0].length ?? 0
      out[k] = {
        first: k === i,
        last: k === j - 1,
        prefixEnd: k === i ? headPrefix.length + (tag?.[0].length ?? 0) : oneLevel,
      }
    }
    i = j
  }
  return out
}

/** If `line` is a callout HEAD (`> [!type] …`), the length of its full `> [!type] ` prefix; else null.
 *  Lets backspace at the head's content-start remove the whole callout cleanly instead of eating the tag. */
export function calloutHeadPrefixLen(line: string): number | null {
  const pfx = blockquotePrefixRe.exec(line)?.[0]
  if (!pfx || !isBlockquoteLine(line)) return null
  const tag = calloutTagRe.exec(line.slice(pfx.length))
  return tag ? pfx.length + tag[0].length : null
}

/** True when the line holding `pos` is part of a callout. Used by input handlers (Shift+Enter stay-in-box). */
export function lineInCallout(doc: string, pos: number): boolean {
  const lines = doc.split('\n')
  let off = 0
  let idx = 0
  for (; idx < lines.length; idx++) {
    const end = off + lines[idx].length
    if (pos <= end) break
    off = end + 1
  }
  return calloutLines(lines)[idx] !== undefined
}

/** Start offset of each line in `text` (parallel to `text.split('\n')`). The one source for the line table
 *  every doc-walking layer needs. */
export function lineOffsets(lines: string[]): number[] {
  const out = new Array<number>(lines.length)
  for (let p = 0, i = 0; i < lines.length; i++) {
    out[i] = p
    p += lines[i].length + 1
  }
  return out
}

export const MAX_NESTING_LEVEL = 3

export function indentLevel(ws: string): number {
  let tabs = 0
  let spaces = 0
  for (const ch of ws) ch === '\t' ? tabs++ : spaces++
  return Math.min(MAX_NESTING_LEVEL, tabs + Math.floor(spaces / 2))
}

/** The single list-marker parser. Every layer reads markers through this — never its own regex.
 *  `kind` is `checkbox` only when a non-empty box follows a `-`/`*`/`+` bullet (`1. [ ]` stays `ordered`).
 *  `arrow` is the `→ ` list (typed `-> `, auto-converted to the glyph by `dashArrow`); it behaves like a
 *  bullet but its marker IS the on-disk glyph, so it's kept as literal source rather than widget-swapped. */
export interface ListMarker {
  kind: 'ordered' | 'bullet' | 'checkbox' | 'arrow'
  bullet?: string
  digits?: string
  level: number
  markerStart: number
  markerEnd: number
  contentStart: number
  box?: { start: number; end: number; inner: string }
  checked?: boolean
}

const LIST_MARKER_RE = /^([ \t]*)(?:(\d+)\.|([-*+•]))(?:[ \t]*(\[([ xX]?)\]))?([ \t]+)(.*)$/d
const ARROW_MARKER_RE = /^([ \t]*)→([ \t]+)/

export function parseListMarker(line: string): ListMarker | null {
  const arrow = ARROW_MARKER_RE.exec(line)
  if (arrow) {
    const markerStart = arrow[1].length
    return {
      kind: 'arrow',
      bullet: '→',
      level: indentLevel(arrow[1]),
      markerStart,
      markerEnd: markerStart + 1,
      contentStart: markerStart + 1 + arrow[2].length,
    }
  }
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
    return {
      kind: 'checkbox',
      bullet,
      level,
      markerStart,
      markerEnd: box.end,
      contentStart,
      box,
      checked: box.inner !== ' ',
    }
  }
  if (m[2] !== undefined) {
    return {
      kind: 'ordered',
      digits: m[2],
      level,
      markerStart,
      markerEnd: markerStart + m[2].length + 1,
      contentStart,
      box,
    }
  }
  return {
    kind: 'bullet',
    bullet,
    level,
    markerStart,
    markerEnd: markerStart + (bullet?.length ?? 1),
    contentStart,
    box,
  }
}

/** parseListMarker that also sees a list behind a `>`/callout prefix — offsets stay full-line-relative, so
 *  callers (drag, format) treat a callout list item exactly like a top-level one. */
export function parseListMarkerPrefixed(line: string): ListMarker | null {
  const pfx = blockquotePrefixRe.exec(line)?.[0]
  // Only strip a prefix the renderer also treats as a quote (`>x` with no space isn't one) — keeps the drag /
  // renumber layers from seeing a list the user can't see.
  if (!pfx || !isBlockquoteLine(line)) return parseListMarker(line)
  const lm = parseListMarker(line.slice(pfx.length))
  if (!lm) return null
  const s = pfx.length
  return {
    ...lm,
    markerStart: lm.markerStart + s,
    markerEnd: lm.markerEnd + s,
    contentStart: lm.contentStart + s,
    box: lm.box ? { ...lm.box, start: lm.box.start + s, end: lm.box.end + s } : undefined,
  }
}

const taskMarkerRegex = /^[ \t]*[-*+][ \t]*\[[ xX]\][ \t]+/
const headingPrefilter = /^[ ]{0,3}#{1,6}([ \t]|$)/
const blockquotePrefilter = /^[ \t]*>+[ \t]/

export function isThematicBreakLine(line: string): boolean {
  const t = line.trim()
  if (t.length < 3 || (t[0] !== '-' && t[0] !== '*' && t[0] !== '_')) return false
  return parse(line).children.some((n) => n.type === 'thematicBreak')
}

export function isHeadingLine(line: string): boolean {
  if (!headingPrefilter.test(line)) return false
  return parse(line).children.some((n) => n.type === 'heading')
}

const headingPartsRe = /^(\s{0,3})(#{1,6})([ \t]+)(.*)$/
/** Decomposes a heading line into its pieces (null if not a syntactic ATX heading). The one heading-shape
 *  regex — level is `hashes.length`, the content start is `indent+hashes+space`. */
export function headingParts(
  line: string,
): { indent: string; hashes: string; space: string; content: string } | null {
  const m = headingPartsRe.exec(line)
  return m ? { indent: m[1], hashes: m[2], space: m[3], content: m[4] } : null
}

/** Needs whitespace after the last `>`: `> a` and `>> a` activate; `>a`, `>>a`, bare `>` do not. */
export function isBlockquoteLine(line: string): boolean {
  if (!blockquotePrefilter.test(line)) return false
  return parse(line).children.some((n) => n.type === 'blockquote')
}

export function hasCheckbox(line: string): boolean {
  return taskMarkerRegex.test(line)
}

/** Inline-math gate: keeps prose / currency `$…$` from tokenizing as math. */
export function isInlineMathContent(content: string): boolean {
  if (/^[+-]?(\d{1,3}(?:,\d{3})*|\d+)(?:\.\d+)?$/.test(content)) return false // currency
  const mathyCount = (content.match(/[\\^_{}=+\-*/<>]/g) ?? []).length
  if (mathyCount === 0) return /^[A-Za-z]{1,3}$/.test(content)
  const tokens = content.split(/\s+/).filter(Boolean).length
  if (mathyCount >= 3) return tokens <= 120
  if (mathyCount === 2) return tokens <= 40
  return tokens <= 6
}
