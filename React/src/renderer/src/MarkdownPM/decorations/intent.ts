import type { Token, TokenKind } from '../tokens'
import { isThematicBreakLine, isHeadingLine, isBlockquoteLine, parseListMarker, blockquotePrefixRe } from '../detect'

// Shared marker class on all three list glyphs (bullet • / checkbox box / ordered number). The drag
// extension targets this one class, and `.md-li-glyph { cursor: pointer }` paints the pointer cursor —
// so any future list syntax that adopts it inherits both the cursor and drag-to-reorder for free.
export const GLYPH_CLASS = 'md-li-glyph'

const HEADING_RE = /^(\s{0,3})(#{1,6})([ \t]+)(.*)$/

const FENCE_RE = /^\s*```/
interface FenceInfo {
  role: 'open' | 'content' | 'close'
  from: number
  to: number
}

interface FenceBlock {
  from: number
  to: number
  open: number
  close: number
  closed: boolean
}

function splitWithOffsets(text: string): { lines: string[]; lineStarts: number[] } {
  const lines = text.split('\n')
  const lineStarts: number[] = []
  for (let p = 0, k = 0; k < lines.length; k++) {
    lineStarts.push(p)
    p += lines[k].length + 1
  }
  return { lines, lineStarts }
}

// One scan of ``` fences → block extents. Shared by the per-line role map (scanFencedCode) and the flat
// range list (fencedCodeRanges) so the two never drift on what counts as a code block.
function fenceBlocks(lines: string[], lineStarts: number[]): FenceBlock[] {
  const blocks: FenceBlock[] = []
  let i = 0
  while (i < lines.length) {
    if (!FENCE_RE.test(lines[i])) {
      i++
      continue
    }
    let j = i + 1
    while (j < lines.length && !FENCE_RE.test(lines[j])) j++
    const closed = j < lines.length
    const close = closed ? j : lines.length - 1
    blocks.push({ from: lineStarts[i], to: lineStarts[close] + lines[close].length, open: i, close, closed })
    i = j + 1
  }
  return blocks
}

function scanFencedCode(lines: string[], lineStarts: number[]): (FenceInfo | undefined)[] {
  const out: (FenceInfo | undefined)[] = new Array(lines.length)
  for (const blk of fenceBlocks(lines, lineStarts)) {
    out[blk.open] = { role: 'open', from: blk.from, to: blk.to }
    const contentEnd = blk.closed ? blk.close : blk.close + 1 // unclosed → the last line is content too
    for (let k = blk.open + 1; k < contentEnd; k++) out[k] = { role: 'content', from: blk.from, to: blk.to }
    if (blk.closed) out[blk.close] = { role: 'close', from: blk.from, to: blk.to }
  }
  return out
}

// Absolute [from, to) ranges of fenced code blocks across the whole doc. The decoration builder drops
// inline tokens that land inside a fence opened above the viewport — which a viewport-only tokenize
// can't see. `to` reaches the end of the closing fence line (or EOF for an unclosed fence).
export function fencedCodeRanges(text: string): [number, number][] {
  const { lines, lineStarts } = splitWithOffsets(text)
  return fenceBlocks(lines, lineStarts).map((b) => [b.from, b.to])
}

export type WidgetSpec =
  | { type: 'hr' }
  | { type: 'bullet' }
  | { type: 'checkbox'; bracketFrom: number; bracketTo: number; checked: boolean }

export type DecoIntent =
  | { kind: 'class'; from: number; to: number; className: string }
  | { kind: 'hide'; from: number; to: number }
  | { kind: 'widget'; from: number; to: number; spec: WidgetSpec }
  | { kind: 'line'; from: number; className: string; level?: number }

export const CONTENT_CLASS: Partial<Record<TokenKind, string>> = {
  bold: 'md-bold',
  italic: 'md-italic',
  strikethrough: 'md-strike',
  inlineCode: 'md-code',
  imageEmbed: 'md-image',
  inlineLatex: 'md-latex',
  blockLatex: 'md-latex'
}

export function decorationsFor(text: string, tokens: Token[], active: Set<number>, selStart: number): DecoIntent[] {
  const intents: DecoIntent[] = []

  tokens.forEach((tk, i) => {
    if (tk.kind === 'wikiLink') return // resolution-dependent; rendered in decorations.ts by status
    if (tk.kind === 'link') return // validity-dependent; rendered in decorations.ts (valid vs invalid)
    const cls = CONTENT_CLASS[tk.kind]
    if (cls) intents.push({ kind: 'class', from: tk.contentRange[0], to: tk.contentRange[1], className: cls })
    if (!active.has(i)) for (const [s, e] of tk.markerRanges) intents.push({ kind: 'hide', from: s, to: e })
  })

  const { lines, lineStarts } = splitWithOffsets(text)
  const fences = scanFencedCode(lines, lineStarts)

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    const ls = lineStarts[i]
    const le = ls + line.length
    const caretOnLine = selStart >= ls && selStart <= le
    const fence = fences[i]
    const lm = parseListMarker(line)
    // A list line reveals its raw source when the caret sits on the marker (shared by bullet + checkbox).
    const onMarker = lm !== null && selStart >= ls + lm.markerStart && selStart <= ls + lm.markerEnd

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
        intents.push({ kind: 'class', from: ls, to: le, className: `md-h${level}` })
        if (contentStart > ls) intents.push({ kind: 'class', from: ls, to: contentStart, className: 'md-hmarker' })
        if (!caretOnLine) intents.push({ kind: 'hide', from: ls, to: contentStart })
      }
    } else if (lm?.kind === 'checkbox' && lm.box) {
      // Raw `- [ ] ` shows only when the caret is on the marker; else a checkbox widget takes its slot.
      intents.push({ kind: 'line', from: ls, className: 'md-li md-li-task', level: lm.level })
      if (lm.markerStart > 0) intents.push({ kind: 'hide', from: ls, to: ls + lm.markerStart })
      if (!onMarker) {
        intents.push({ kind: 'hide', from: ls + lm.markerStart, to: ls + lm.box.start })
        intents.push({
          kind: 'widget',
          from: ls + lm.box.start,
          to: ls + lm.box.end,
          spec: { type: 'checkbox', bracketFrom: ls + lm.box.start, bracketTo: ls + lm.box.end, checked: lm.checked ?? false }
        })
        intents.push({ kind: 'hide', from: ls + lm.box.end, to: ls + lm.contentStart })
      }
    } else if (lm?.kind === 'bullet' && lm.bullet === '-' && !lm.box) {
      // Raw `-` shows only when the caret is on the marker; else a `•` widget takes its exact slot.
      intents.push({ kind: 'line', from: ls, className: 'md-li', level: lm.level })
      if (lm.markerStart > 0) intents.push({ kind: 'hide', from: ls, to: ls + lm.markerStart })
      if (!onMarker) intents.push({ kind: 'widget', from: ls + lm.markerStart, to: ls + lm.markerEnd, spec: { type: 'bullet' } })
    } else if (lm?.kind === 'arrow' || (lm?.kind === 'bullet' && lm.bullet === '+' && !lm.box)) {
      // `→` and `+` ARE their own glyphs, so they stay as literal source (like the ordered number, not a
      // widget): recoloured to the marker tone + given the drag-handle class. Share the `.md-li` bullet zone.
      intents.push({ kind: 'line', from: ls, className: 'md-li', level: lm.level })
      if (lm.markerStart > 0) intents.push({ kind: 'hide', from: ls, to: ls + lm.markerStart })
      intents.push({ kind: 'class', from: ls + lm.markerStart, to: ls + lm.markerEnd, className: `md-control ${GLYPH_CLASS}` })
    } else if (lm?.kind === 'ordered') {
      // `N.` stays literal recoloured source (no widget) so typing after the number can't hit an atomic range.
      intents.push({ kind: 'line', from: ls, className: 'md-li md-li-ordered', level: lm.level })
      if (lm.markerStart > 0) intents.push({ kind: 'hide', from: ls, to: ls + lm.markerStart })
      intents.push({ kind: 'class', from: ls + lm.markerStart, to: ls + lm.markerEnd, className: `md-ol-marker md-control ${GLYPH_CLASS}` })
      // Hide the source space so the gap is the zone padding.
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
