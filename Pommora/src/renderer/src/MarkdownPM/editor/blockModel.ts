// The unified block resolver for block-drag: what top-level block owns a line, its extent, its kind. Pure
// source-string logic (no CM6 / DOM) so it's unit-testable, and the drag layer reads boundaries through it alone.
//
// `to` is EXCLUSIVE of the trailing newline — matching SubBlock.to / headingSections.to / TableRegion.to,
// which the drag's self-drop guard relies on. Do not return an inclusive `to`.
//
// Block math (`$$…$$`) is intentionally NOT a distinct kind: it's a span token. A multi-line `$$…$$` containing
// a blank line splits into two paragraphs with orphaned `$$` (the one known V1 gap — it CORRUPTS, not just
// mis-selects; fix with a `blockMathRanges` when it earns it).
import {
  calloutLines,
  isBlockquoteLine,
  isHeadingLine,
  isThematicBreakLine,
  lineOffsets,
  parseListMarkerPrefixed,
  type CalloutLine,
} from '../detect'
import { fencedCodeRanges } from '../decorations/intent'
import { tableRegions } from '../Tables/regions'
import { headingSections } from './folding'

export type BlockKind =
  | 'heading'
  | 'list'
  | 'callout'
  | 'blockquote'
  | 'code'
  | 'table'
  | 'hr'
  | 'paragraph'

export interface Block {
  from: number // line start of the block's first line
  to: number // line end of the block's last line, exclusive of the trailing newline
  kind: BlockKind
}

// Per-line classification shared by blockAt + blockStarts: the line table and every "what owns this line"
// predicate, built once. `kindAt(i)` returns the membership kind of line i (paragraph here means "claimed by
// nothing else") or null on a blank line; `claimed` is the paragraph-boundary test.
interface BlockContext {
  lines: string[]
  n: number
  starts: number[]
  ends: number[]
  callout: (CalloutLine | undefined)[]
  listMember: boolean[]
  claimed: (i: number) => boolean
  kindAt: (i: number) => BlockKind | null
}

function blockContext(doc: string): BlockContext {
  const lines = doc.split('\n')
  const n = lines.length
  const starts = lineOffsets(lines)
  const ends = starts.map((s, i) => s + lines[i].length)

  const callout = calloutLines(lines)
  const fences = fencedCodeRanges(doc)
  const tables = tableRegions(doc)
  const inFence = (i: number): boolean =>
    i >= 0 && i < n && fences.some(([f, t]) => starts[i] >= f && starts[i] <= t)
  const inTable = (i: number): boolean =>
    i >= 0 && i < n && tables.some((r) => starts[i] >= r.from && starts[i] <= r.to)

  // List membership: marker lines PLUS their indented continuations (a wrapped item body), but only where a
  // run actually holds a marker — so a bare indented paragraph isn't swept in. A blank line breaks a run, so
  // blank-separated "loose" items split into separate list blocks (a V1 decision); a multi-line item stays whole.
  const isMarker = (i: number): boolean => parseListMarkerPrefixed(lines[i]) !== null
  const isListCont = (i: number): boolean => lines[i].trim() !== '' && /^[ \t]/.test(lines[i])
  const listMember = new Array<boolean>(n).fill(false)
  for (let i = 0; i < n; ) {
    if (!isMarker(i) && !isListCont(i)) {
      i++
      continue
    }
    let j = i
    while (j + 1 < n && (isMarker(j + 1) || isListCont(j + 1))) j++
    let hasMarker = false
    for (let k = i; k <= j && !hasMarker; k++) hasMarker = isMarker(k)
    if (hasMarker) for (let k = i; k <= j; k++) listMember[k] = true
    i = j + 1
  }

  const heading = lines.map(isHeadingLine)
  const hr = lines.map(isThematicBreakLine)
  const bq = lines.map(isBlockquoteLine)
  const claimed = (i: number): boolean =>
    i < 0 ||
    i >= n ||
    lines[i].trim() === '' ||
    !!callout[i] ||
    bq[i] ||
    inFence(i) ||
    inTable(i) ||
    heading[i] ||
    listMember[i] ||
    hr[i]

  // Box-first precedence: a callout/quote line resolves to its box; code/table beat heading/list so a `#`/`-`
  // inside a fence or table isn't mis-read; hr beats paragraph so it's never absorbed. paragraph is the catch-all.
  const kindAt = (i: number): BlockKind | null => {
    if (i < 0 || i >= n) return null // a neighbour-lookup off either doc edge owns no block
    if (lines[i].trim() === '') return null
    if (callout[i]) return 'callout'
    if (bq[i]) return 'blockquote'
    if (inFence(i)) return 'code'
    if (inTable(i)) return 'table'
    if (heading[i]) return 'heading'
    if (listMember[i]) return 'list'
    if (hr[i]) return 'hr'
    return 'paragraph'
  }

  return { lines, n, starts, ends, callout, listMember, claimed, kindAt }
}

/** The top-level block owning the line at `pos`, or null on a blank/unowned line (nothing to grab). */
export function blockAt(doc: string, pos: number): Block | null {
  const ctx = blockContext(doc)
  const { n, starts, ends, callout, listMember } = ctx

  // The line holding pos: the first whose end (pre-newline) is at/after pos.
  let li = n - 1
  for (let i = 0; i < n; i++) {
    if (pos <= ends[i]) {
      li = i
      break
    }
  }
  const kind = ctx.kindAt(li)
  if (kind === null) return null

  switch (kind) {
    case 'callout': {
      let a = li
      while (a > 0 && callout[a] && !callout[a]!.first) a--
      let b = li
      while (b < n - 1 && callout[b] && !callout[b]!.last) b++
      return { from: starts[a], to: ends[b], kind: 'callout' }
    }
    case 'blockquote': {
      let a = li
      while (a > 0 && !callout[a - 1] && ctx.kindAt(a - 1) === 'blockquote') a--
      let b = li
      while (b < n - 1 && !callout[b + 1] && ctx.kindAt(b + 1) === 'blockquote') b++
      return { from: starts[a], to: ends[b], kind: 'blockquote' }
    }
    case 'code':
      return fenceBlockAt(doc, starts[li])
    case 'table':
      return tableBlockAt(doc, starts[li])
    case 'heading': {
      const sec = headingSections(doc).find((s) => s.from === starts[li])
      return sec
        ? { from: sec.from, to: sec.to, kind: 'heading' }
        : { from: starts[li], to: ends[li], kind: 'heading' }
    }
    case 'list': {
      let a = li
      while (a > 0 && listMember[a - 1]) a--
      let b = li
      while (b < n - 1 && listMember[b + 1]) b++
      return { from: starts[a], to: ends[b], kind: 'list' }
    }
    case 'hr':
      return { from: starts[li], to: ends[li], kind: 'hr' }
    case 'paragraph': {
      let a = li
      while (a > 0 && !ctx.claimed(a - 1)) a--
      let b = li
      while (b < n - 1 && !ctx.claimed(b + 1)) b++
      return { from: starts[a], to: ends[b], kind: 'paragraph' }
    }
  }
}

function fenceBlockAt(doc: string, lineStart: number): Block {
  const f = fencedCodeRanges(doc).find(([ff, tt]) => lineStart >= ff && lineStart <= tt)!
  return { from: f[0], to: f[1], kind: 'code' }
}

function tableBlockAt(doc: string, lineStart: number): Block {
  const r = tableRegions(doc).find((rr) => lineStart >= rr.from && lineStart <= rr.to)!
  return { from: r.from, to: r.to, kind: 'table' }
}

export interface BlockStart {
  from: number
  kind: BlockKind
}

/** Every draggable block's first-line offset + kind, in document order — a heading line and each block inside
 *  its section both qualify; continuation/blank lines don't. The shared basis for where handles render and
 *  where a drag can drop. Single pass over the shared block context (was O(n²) via `blockAt`-per-line). */
export function blockStarts(doc: string): BlockStart[] {
  const ctx = blockContext(doc)
  const { n, starts, callout, listMember } = ctx
  const out: BlockStart[] = []
  for (let i = 0; i < n; i++) {
    const kind = ctx.kindAt(i)
    if (kind === null) continue
    // Only the FIRST line of a multi-line block starts a draggable block (a continuation line repeats its kind).
    let first: boolean
    switch (kind) {
      case 'callout':
        first = !!callout[i]!.first
        break
      case 'blockquote':
        first = i === 0 || ctx.kindAt(i - 1) !== 'blockquote' || !!callout[i - 1]
        break
      case 'code':
        first = ctx.kindAt(i - 1) !== 'code'
        break
      case 'table':
        first = ctx.kindAt(i - 1) !== 'table'
        break
      case 'list':
        first = !listMember[i - 1]
        break
      case 'paragraph':
        first = ctx.claimed(i - 1)
        break
      default:
        first = true // heading + hr are always single-line block starts
    }
    if (first) out.push({ from: starts[i], kind })
  }
  return out
}
