import type { Token, TokenKind } from '../tokens'
import {
  isThematicBreakLine,
  isHeadingLine,
  isBlockquoteLine,
  parseListMarker,
  blockquotePrefixRe,
  quoteDepth,
  calloutLines,
  headingParts,
  lineOffsets,
  type CalloutLine
} from '../detect'

// A line is a nested quote INSIDE a callout when it's a callout line whose content (after the callout's own
// `>` level) is itself a blockquote. Drives the md-bq-in run's first/last across a contiguous nested-quote run.
function calloutNestedQuote(lines: string[], callouts: (CalloutLine | undefined)[], k: number): boolean {
  const co = k >= 0 && k < lines.length ? callouts[k] : undefined
  if (!co) return false
  const inner = lines[k].slice(co.prefixEnd)
  return blockquotePrefixRe.test(inner) && isBlockquoteLine(inner)
}

// Shared marker class on all three list glyphs (bullet • / checkbox box / ordered number). The drag
// extension targets this one class, and `.md-li-glyph { cursor: pointer }` paints the pointer cursor —
// so any future list syntax that adopts it inherits both the cursor and drag-to-reorder for free.
export const GLYPH_CLASS = 'md-li-glyph'

// A ``` fence, capturing its `>` prefix so open/close pair by quote-DEPTH: a `> ``` opens a callout/quote-internal
// block closed only by another `> ``` (a bare ``` is a separate top-level block), and a quoted fence ends when its
// blockquote does. Without the depth match, a top-level code block quoting a ``` (`> ```` as content) corrupts.
const FENCE_RE = /^([ \t]*(?:>[ \t]?)*)```/
const fenceDepth = (line: string): number => {
  const m = FENCE_RE.exec(line)
  return m ? (m[1].match(/>/g)?.length ?? 0) : -1 // -1 = not a fence marker
}
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
  return { lines, lineStarts: lineOffsets(lines) }
}

// One scan of ``` fences → block extents. Shared by the per-line role map (scanFencedCode) and the flat
// range list (fencedCodeRanges) so the two never drift on what counts as a code block.
function fenceBlocks(lines: string[], lineStarts: number[]): FenceBlock[] {
  const blocks: FenceBlock[] = []
  let i = 0
  while (i < lines.length) {
    const d = fenceDepth(lines[i])
    if (d === -1) {
      i++
      continue
    }
    // The close is a fence marker at the SAME depth; the block also ends if the surrounding blockquote drops
    // below that depth (a quoted fence can't outlive its `>` lines).
    let j = i + 1
    while (j < lines.length && fenceDepth(lines[j]) !== d && quoteDepth(lines[j]) >= d) j++
    const closed = j < lines.length && fenceDepth(lines[j]) === d
    const close = closed ? j : j - 1 // unclosed → the last line still in the block (the open itself if j === i+1)
    blocks.push({ from: lineStarts[i], to: lineStarts[close] + lines[close].length, open: i, close, closed })
    i = closed ? j + 1 : j
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
  | { type: 'checkbox'; bracketFrom: number; checked: boolean }

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
  const callouts = calloutLines(lines)

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    const ls = lineStarts[i]
    const le = ls + line.length

    // Box chrome (callout/quote) is independent of what's inside it: a `> - item` gets BOTH the box line-class
    // AND the bullet, a `> ```` code block keeps its box. `base` is where the inner content begins, so every
    // construct renders identically whether it's top-level or behind a `>` prefix.
    let base = 0
    const co = callouts[i]
    if (co) {
      intents.push({ kind: 'line', from: ls, className: `md-callout${co.first ? ' md-callout-first' : ''}${co.last ? ' md-callout-last' : ''}` })
      base = co.prefixEnd
      // A blockquote nested inside the callout (`> > …`): render the inner `>` as an inset quote block (indent
      // + bar + fill) rather than flattening it to plain callout body. first/last come from the quote depth.
      const inner = line.slice(base)
      const qm = blockquotePrefixRe.exec(inner) // all remaining `>` levels → one inset quote (depth flattens)
      if (qm && isBlockquoteLine(inner)) {
        // first/last span the contiguous run of nested-quote lines (not a depth match — a run can vary in depth
        // yet flatten to one block), mirroring how the plain-quote branch tests its neighbours.
        const first = !calloutNestedQuote(lines, callouts, i - 1)
        const last = !calloutNestedQuote(lines, callouts, i + 1)
        intents.push({ kind: 'line', from: ls, className: `md-bq-in${first ? ' md-bq-in-first' : ''}${last ? ' md-bq-in-last' : ''}` })
        base += qm[0].length
      }
    } else if (isBlockquoteLine(line)) {
      const bm = blockquotePrefixRe.exec(line)
      if (bm) {
        const first = i === 0 || !isBlockquoteLine(lines[i - 1])
        const last = i === lines.length - 1 || !isBlockquoteLine(lines[i + 1])
        intents.push({ kind: 'line', from: ls, className: `md-bq${first ? ' md-bq-first' : ''}${last ? ' md-bq-last' : ''}` })
        base = bm[0].length
      }
    }

    const fence = fences[i]
    if (fence) {
      // Code block (composes with box chrome). Hide the `>` prefix, then hide the ``` fence line itself (after
      // the prefix) unless the caret is in the block. Content lines show as code.
      const innerStart = ls + base
      const caretInBlock = selStart >= fence.from && selStart <= fence.to
      intents.push({ kind: 'line', from: ls, className: `md-cb${fence.role === 'open' ? ' md-cb-first' : ''}${fence.role === 'close' ? ' md-cb-last' : ''}` })
      if (base > 0) intents.push({ kind: 'hide', from: ls, to: innerStart })
      if (fence.role !== 'content' && !caretInBlock) intents.push({ kind: 'hide', from: innerStart, to: le })
      continue
    }

    // pushConstruct hides the prefix [ls, innerStart] itself, so a leading bullet/HR widget can ABSORB it into
    // one replace — CM drops a widget-replace that merely *touches* a preceding replace at the same offset.
    pushConstruct(intents, line, ls, base, selStart)
  }

  return intents
}

// Reads the construct from `line.slice(base)` so it works identically top-level (base 0) or behind a
// `>`/callout prefix; offsets are absolute (`ls + base`), and the line-class attaches at `ls` to compose with box chrome.
function pushConstruct(intents: DecoIntent[], line: string, ls: number, base: number, selStart: number): void {
  const inner = base === 0 ? line : line.slice(base)
  const innerStart = ls + base
  const le = ls + line.length
  const caretOnLine = selStart >= ls && selStart <= le
  const lm = parseListMarker(inner)
  const onMarker = lm !== null && selStart >= innerStart + lm.markerStart && selStart <= innerStart + lm.markerEnd

  // A leading bullet/HR widget absorbs the box prefix into one replace (CM drops a widget-replace that just
  // touches a preceding replace). Otherwise hide the prefix separately so the `>`/`[!type]` never shows.
  const bulletAbsorbs = base > 0 && !onMarker && lm?.kind === 'bullet' && lm.bullet === '-' && !lm.box
  const hrAbsorbs = base > 0 && !caretOnLine && lm === null && isThematicBreakLine(inner)
  if (base > 0 && !bulletAbsorbs && !hrAbsorbs) intents.push({ kind: 'hide', from: ls, to: innerStart })

  if (isHeadingLine(inner)) {
    const hm = headingParts(inner)
    if (hm) {
      const level = hm.hashes.length
      const contentStart = innerStart + hm.indent.length + hm.hashes.length + hm.space.length
      intents.push({ kind: 'class', from: innerStart, to: le, className: `md-h${level}` })
      if (contentStart > innerStart) intents.push({ kind: 'class', from: innerStart, to: contentStart, className: 'md-hmarker' })
      if (!caretOnLine) intents.push({ kind: 'hide', from: innerStart, to: contentStart })
    }
  } else if (lm?.kind === 'checkbox' && lm.box) {
    // Raw `- [ ] ` shows only when the caret is on the marker; else a checkbox widget takes its slot.
    intents.push({ kind: 'line', from: ls, className: 'md-li md-li-task', level: lm.level })
    if (lm.markerStart > 0) intents.push({ kind: 'hide', from: innerStart, to: innerStart + lm.markerStart })
    if (!onMarker) {
      intents.push({ kind: 'hide', from: innerStart + lm.markerStart, to: innerStart + lm.box.start })
      intents.push({
        kind: 'widget',
        from: innerStart + lm.box.start,
        to: innerStart + lm.box.end,
        spec: { type: 'checkbox', bracketFrom: innerStart + lm.box.start, checked: lm.checked ?? false }
      })
      intents.push({ kind: 'hide', from: innerStart + lm.box.end, to: innerStart + lm.contentStart })
    }
  } else if (lm?.kind === 'bullet' && lm.bullet === '-' && !lm.box) {
    // Raw `-` shows only when the caret is on the marker; else a `•` widget takes its exact slot. Inside a box
    // the widget swallows the prefix too (`> -` → `•`) so it doesn't render-fail by touching the prefix-hide.
    intents.push({ kind: 'line', from: ls, className: 'md-li', level: lm.level })
    if (onMarker) {
      if (lm.markerStart > 0) intents.push({ kind: 'hide', from: innerStart, to: innerStart + lm.markerStart })
    } else {
      intents.push({ kind: 'widget', from: bulletAbsorbs ? ls : innerStart + lm.markerStart, to: innerStart + lm.markerEnd, spec: { type: 'bullet' } })
    }
  } else if (lm?.kind === 'arrow' || (lm?.kind === 'bullet' && lm.bullet === '+' && !lm.box)) {
    // `→` and `+` ARE their own glyphs, so they stay literal source (like the ordered number): recoloured +
    // given the drag-handle class. Share the `.md-li` bullet zone.
    intents.push({ kind: 'line', from: ls, className: 'md-li', level: lm.level })
    if (lm.markerStart > 0) intents.push({ kind: 'hide', from: innerStart, to: innerStart + lm.markerStart })
    intents.push({ kind: 'class', from: innerStart + lm.markerStart, to: innerStart + lm.markerEnd, className: `md-control ${GLYPH_CLASS}` })
  } else if (lm?.kind === 'ordered') {
    // `N.` stays literal recoloured source (no widget) so typing after the number can't hit an atomic range.
    intents.push({ kind: 'line', from: ls, className: 'md-li md-li-ordered', level: lm.level })
    if (lm.markerStart > 0) intents.push({ kind: 'hide', from: innerStart, to: innerStart + lm.markerStart })
    intents.push({ kind: 'class', from: innerStart + lm.markerStart, to: innerStart + lm.markerEnd, className: `md-ol-marker md-control ${GLYPH_CLASS}` })
    intents.push({ kind: 'hide', from: innerStart + lm.markerEnd, to: innerStart + lm.contentStart })
  } else if (isThematicBreakLine(inner) && !caretOnLine) {
    // Inside a box the HR widget swallows the prefix (same touching-replace reason as the bullet).
    intents.push({ kind: 'widget', from: hrAbsorbs ? ls : innerStart, to: le, spec: { type: 'hr' } })
  }
}
