// Decoration-intent mapping — still framework-free. Turns detected tokens + caret state into a
// flat list of intents (which Styles.css class, which marker ranges to hide, which widget to
// draw + its data). The CM6 adapter (editor/decorations) is the ONLY thing that converts these
// into real CM6 decorations; keeping this layer pure data means it's unit-testable without an
// editor and the behavior layer never holds a CSS literal — only class names + widget specs.
import type { Token, TokenKind } from '../tokens'
import {
  isThematicBreakLine,
  isHeadingLine,
  isDashBulletLine,
  isOrderedListLine,
  isBlockquoteLine,
  hasCheckbox
} from '../detect'

const HEADING_RE = /^(\s{0,3})(#{1,6})([ \t]+)(.*)$/
const BULLET_RE = /^([ \t]*)(-[ \t]+)/
const ORDERED_RE = /^([ \t]*)(\d+)\.[ \t]+/
const CHECKBOX_RE = /^([ \t]*)[-*+][ \t]*(\[[ xX]\])[ \t]+/d
const BLOCKQUOTE_RE = /^[ \t]*(?:>[ \t]?)+/

/** Source-indent → visual nesting level (`level = tabs + ⌊spaces/2⌋`, capped at 3 — spec §6.2). */
function indentLevel(ws: string): number {
  let tabs = 0
  let spaces = 0
  for (const ch of ws) ch === '\t' ? tabs++ : spaces++
  return Math.min(3, tabs + Math.floor(spaces / 2))
}

const FENCE_RE = /^\s*```/
/** A fenced-code-block line's role + the block's char range (so the caret-in-block test is cheap). */
interface FenceInfo {
  role: 'open' | 'content' | 'close'
  from: number
  to: number
}

/** Classify every line as part of a fenced code block (or not). Mirrors `isInsideCode`'s doc-scan:
 *  toggle on ``` lines. An unclosed fence runs to the document end. */
function scanFencedCode(lines: string[], lineStarts: number[]): (FenceInfo | undefined)[] {
  const out: (FenceInfo | undefined)[] = new Array(lines.length)
  let i = 0
  while (i < lines.length) {
    if (!FENCE_RE.test(lines[i])) {
      i++
      continue
    }
    let j = i + 1
    while (j < lines.length && !FENCE_RE.test(lines[j])) j++
    const closeLine = j < lines.length ? j : lines.length - 1
    const from = lineStarts[i]
    const to = lineStarts[closeLine] + lines[closeLine].length
    out[i] = { role: 'open', from, to }
    for (let k = i + 1; k < j; k++) out[k] = { role: 'content', from, to }
    if (j < lines.length) out[j] = { role: 'close', from, to }
    i = j + 1
  }
  return out
}

/** A widget to draw in place of source text, with the data its renderer needs. */
export type WidgetSpec =
  | { type: 'hr' }
  | { type: 'bullet' }
  | { type: 'ordered'; label: string }
  | { type: 'checkbox'; bracketFrom: number; bracketTo: number; checked: boolean }

export type DecoIntent =
  | { kind: 'class'; from: number; to: number; className: string }
  | { kind: 'hide'; from: number; to: number }
  | { kind: 'widget'; from: number; to: number; spec: WidgetSpec }
  /** A whole-line decoration (`from` = line start). `level` (lists only) rides as a CSS var for
   *  the per-level indent; omit it for non-list line chrome (e.g. the blockquote card). */
  | { kind: 'line'; from: number; className: string; level?: number }

/** Inline token kind → the Styles.css class applied to its content. */
const CONTENT_CLASS: Partial<Record<TokenKind, string>> = {
  bold: 'md-bold',
  italic: 'md-italic',
  strikethrough: 'md-strike',
  inlineCode: 'md-code',
  link: 'md-link',
  wikiLink: 'md-connection',
  imageEmbed: 'md-image',
  inlineLatex: 'md-latex',
  blockLatex: 'md-latex'
}

/**
 * Build the decoration intents for a document.
 * - Inline tokens: a content class always; markers hidden unless the token is active (caret on it).
 * - Headings: a size class on the title + the `#` markers hidden caret-out.
 * - Lists/checkboxes: always-show glyph widgets (• / a checkbox box) over the source marker.
 * - HR: a rule widget caret-out; literal `---` when the caret is on the line.
 */
export function decorationsFor(text: string, tokens: Token[], active: Set<number>, selStart: number): DecoIntent[] {
  const intents: DecoIntent[] = []

  tokens.forEach((tk, i) => {
    const cls = CONTENT_CLASS[tk.kind]
    if (cls) intents.push({ kind: 'class', from: tk.contentRange[0], to: tk.contentRange[1], className: cls })
    if (!active.has(i)) {
      for (const [s, e] of tk.markerRanges) intents.push({ kind: 'hide', from: s, to: e })
    }
  })

  const lines = text.split('\n')
  const lineStarts: number[] = []
  for (let p = 0, k = 0; k < lines.length; k++) {
    lineStarts.push(p)
    p += lines[k].length + 1
  }
  const fences = scanFencedCode(lines, lineStarts)

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    const ls = lineStarts[i]
    const le = ls + line.length
    const caretOnLine = selStart >= ls && selStart <= le
    const fence = fences[i]

    if (fence) {
      // Code block line: the whole block gets the code background + mono via `md-cb`; the open/close
      // fence markers hide when the caret is outside the block (dynamic syntax), reveal when inside.
      const caretInBlock = selStart >= fence.from && selStart <= fence.to
      const className = `md-cb${fence.role === 'open' ? ' md-cb-first' : ''}${fence.role === 'close' ? ' md-cb-last' : ''}`
      intents.push({ kind: 'line', from: ls, className })
      if (fence.role !== 'content' && !caretInBlock) intents.push({ kind: 'hide', from: ls, to: le })
    } else if (isHeadingLine(line)) {
      const hm = HEADING_RE.exec(line)
      if (hm) {
        const level = hm[2].length
        const contentStart = ls + hm[1].length + hm[2].length + hm[3].length
        // Size the WHOLE line so the `#` markers grow/shrink with the level too (live, as typed).
        intents.push({ kind: 'class', from: ls, to: le, className: `md-h${level}` })
        // The `#` markers render muted (label-secondary) when visible; hidden when the caret leaves.
        if (contentStart > ls) intents.push({ kind: 'class', from: ls, to: contentStart, className: 'md-hmarker' })
        if (!caretOnLine) intents.push({ kind: 'hide', from: ls, to: contentStart })
      }
    } else if (hasCheckbox(line)) {
      const cm = CHECKBOX_RE.exec(line)
      const bracket = cm?.indices?.[2]
      if (cm && bracket) {
        const [bs, be] = bracket
        // Replace the whole prefix (indent + marker) so nesting comes purely from the line's
        // padding, never literal leading whitespace — keeps the hanging indent exact.
        intents.push({ kind: 'line', from: ls, className: 'md-li', level: indentLevel(cm[1]) })
        intents.push({
          kind: 'widget',
          from: ls,
          to: ls + cm[0].length,
          spec: { type: 'checkbox', bracketFrom: ls + bs, bracketTo: ls + be, checked: cm[2][1].toLowerCase() === 'x' }
        })
      }
    } else if (isDashBulletLine(line)) {
      const bm = BULLET_RE.exec(line)
      if (bm) {
        intents.push({ kind: 'line', from: ls, className: 'md-li', level: indentLevel(bm[1]) })
        intents.push({ kind: 'widget', from: ls, to: ls + bm[0].length, spec: { type: 'bullet' } })
      }
    } else if (isOrderedListLine(line)) {
      const om = ORDERED_RE.exec(line)
      if (om) {
        intents.push({ kind: 'line', from: ls, className: 'md-li', level: indentLevel(om[1]) })
        intents.push({ kind: 'widget', from: ls, to: ls + om[0].length, spec: { type: 'ordered', label: `${om[2]}.` } })
      }
    } else if (isBlockquoteLine(line)) {
      // Always-show card (not caret-aware): the `>` markers are permanently hidden; first/last lines
      // round the card's corners so a run of quote lines reads as one continuous box.
      const bm = BLOCKQUOTE_RE.exec(line)
      if (bm) {
        const first = i === 0 || !isBlockquoteLine(lines[i - 1])
        const last = i === lines.length - 1 || !isBlockquoteLine(lines[i + 1])
        const className = `md-bq${first ? ' md-bq-first' : ''}${last ? ' md-bq-last' : ''}`
        intents.push({ kind: 'line', from: ls, className })
        intents.push({ kind: 'hide', from: ls, to: ls + bm[0].length })
      }
    } else if (isThematicBreakLine(line) && !caretOnLine) {
      intents.push({ kind: 'widget', from: ls, to: le, spec: { type: 'hr' } })
    }
  }

  return intents
}
