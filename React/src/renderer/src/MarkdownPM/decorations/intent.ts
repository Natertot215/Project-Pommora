// Framework-free decoration-intent mapping (tokens + caret state → flat intents, no CSS literals).
// The CM6 adapter (editor/decorations) is the only thing that realizes these, keeping this layer unit-testable without an editor.
import type { Token, TokenKind } from '../tokens'
import { isThematicBreakLine, isHeadingLine, isBlockquoteLine, parseListMarker, blockquotePrefixRe } from '../detect'

const HEADING_RE = /^(\s{0,3})(#{1,6})([ \t]+)(.*)$/

const FENCE_RE = /^\s*```/
/** A fenced-code-block line's role + the block's char range (for a cheap caret-in-block test). */
interface FenceInfo {
  role: 'open' | 'content' | 'close'
  from: number
  to: number
}

/** Classify every line's fenced-code role (toggle on ``` lines); an unclosed fence runs to doc end. */
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

/** A widget to draw in place of source text, with the data its renderer needs. Bullets + ordered
 *  numbers are NOT widgets — they render from their own (hidden / recoloured) source. */
export type WidgetSpec =
  | { type: 'hr' }
  | { type: 'bullet' }
  | { type: 'checkbox'; bracketFrom: number; bracketTo: number; checked: boolean }

export type DecoIntent =
  | { kind: 'class'; from: number; to: number; className: string }
  | { kind: 'hide'; from: number; to: number }
  | { kind: 'widget'; from: number; to: number; spec: WidgetSpec }
  /** Whole-line decoration (`from` = line start). `level` (lists only) rides as a CSS var for the
   *  per-level indent. */
  | { kind: 'line'; from: number; className: string; level?: number }

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

/** Build the decoration intents for a document. Inline markers hide unless their token is active
 *  (caret on it); list/checkbox glyphs and the HR rule are widgets shown over the source marker. */
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
    const lm = parseListMarker(line)

    if (fence) {
      // Fence markers reveal only when the caret is anywhere in the block.
      const caretInBlock = selStart >= fence.from && selStart <= fence.to
      const className = `md-cb${fence.role === 'open' ? ' md-cb-first' : ''}${fence.role === 'close' ? ' md-cb-last' : ''}`
      intents.push({ kind: 'line', from: ls, className })
      if (fence.role !== 'content' && !caretInBlock) intents.push({ kind: 'hide', from: ls, to: le })
    } else if (isHeadingLine(line)) {
      const hm = HEADING_RE.exec(line)
      if (hm) {
        const level = hm[2].length
        const contentStart = ls + hm[1].length + hm[2].length + hm[3].length
        // Size the WHOLE line so the `#` markers grow/shrink with the level too.
        intents.push({ kind: 'class', from: ls, to: le, className: `md-h${level}` })
        if (contentStart > ls) intents.push({ kind: 'class', from: ls, to: contentStart, className: 'md-hmarker' })
        if (!caretOnLine) intents.push({ kind: 'hide', from: ls, to: contentStart })
      }
    } else if (lm?.kind === 'checkbox' && lm.box) {
      intents.push({ kind: 'line', from: ls, className: 'md-li md-li-task', level: lm.level })
      intents.push({ kind: 'hide', from: ls, to: ls + lm.box.start })
      intents.push({
        kind: 'widget',
        from: ls + lm.box.start,
        to: ls + lm.box.end,
        spec: { type: 'checkbox', bracketFrom: ls + lm.box.start, bracketTo: ls + lm.box.end, checked: lm.checked ?? false }
      })
      // Hide the trailing space so the gap to the text is the chip zone's padding, not a rendered space.
      intents.push({ kind: 'hide', from: ls + lm.box.end, to: ls + lm.contentStart })
    } else if (lm?.kind === 'bullet' && lm.bullet === '-' && !lm.box) {
      // Reveal the raw `-` only when the caret is on the marker itself; otherwise a `•` widget takes
      // the dash's exact slot (no horizontal shift).
      const onMarker = selStart >= ls + lm.markerStart && selStart <= ls + lm.markerEnd
      intents.push({ kind: 'line', from: ls, className: 'md-li', level: lm.level })
      if (lm.markerStart > 0) intents.push({ kind: 'hide', from: ls, to: ls + lm.markerStart })
      if (!onMarker) intents.push({ kind: 'widget', from: ls + lm.markerStart, to: ls + lm.markerEnd, spec: { type: 'bullet' } })
    } else if (lm?.kind === 'ordered') {
      // The `N.` stays as literal recoloured source — no widget, so typing after the number can't hit
      // an atomic range; the right-aligned zone (md-ol-marker) columns the periods across digit counts.
      intents.push({ kind: 'line', from: ls, className: 'md-li md-li-ordered', level: lm.level })
      if (lm.markerStart > 0) intents.push({ kind: 'hide', from: ls, to: ls + lm.markerStart })
      intents.push({ kind: 'class', from: ls + lm.markerStart, to: ls + lm.markerEnd, className: 'md-ol-marker md-syntax' })
      // Hide the trailing space — the gap comes from the zone padding (like the checkbox).
      intents.push({ kind: 'hide', from: ls + lm.markerEnd, to: ls + lm.contentStart })
    } else if (isBlockquoteLine(line)) {
      const bm = blockquotePrefixRe.exec(line)
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
