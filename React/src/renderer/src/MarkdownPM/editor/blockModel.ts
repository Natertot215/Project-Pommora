// The unified block resolver for block-drag: "what top-level block owns this line, where does it start/end,
// what kind is it." Pure source-string logic — no CM6 / DOM — so it's unit-testable without an editor, and
// the drag layer reads block boundaries through this single source instead of each gesture re-detecting.
//
// `to` is EXCLUSIVE of the trailing newline — the same convention SubBlock.to / headingSections.to /
// TableRegion.to already use, which the drag's self-drop guard relies on. Do not return an inclusive `to`.
//
// Box-first precedence: a line inside a callout/blockquote resolves to the WHOLE box (its inner list/heading
// is a nested block, deferred to V2). Code/table membership is checked before heading/list so a `#`/`-` line
// inside a fence or table isn't mis-read as a heading/list. The paragraph rule is the catch-all and is bounded
// by every other kind, so an HR / heading / list / box / fence / table is never absorbed into a paragraph.
//
// Block math (`$$…$$`) is intentionally NOT a distinct kind here: it's a span token, not a line-block. A
// single-line `$$x$$` resolves as a paragraph (correct); a multi-line `$$\n…\n$$` resolves as one paragraph
// too (also correct) UNLESS it contains a blank line — then it splits into two paragraphs with orphaned `$$`
// (the one known V1 gap; it CORRUPTS, not just mis-selects — fix with a `blockMathRanges` when it earns it).
// A blockquote's LAZY continuation (a non-`>` line under it) likewise ends its run — rare here, since Enter
// auto-prefixes `>`.
import { calloutLines, isBlockquoteLine, isHeadingLine, isThematicBreakLine, parseListMarkerPrefixed } from '../detect'
import { fencedCodeRanges } from '../decorations/intent'
import { tableRegions } from '../Tables/regions'
import { headingSections } from './folding'

export type BlockKind = 'heading' | 'list' | 'callout' | 'blockquote' | 'code' | 'table' | 'hr' | 'paragraph'

export interface Block {
  from: number // line start of the block's first line
  to: number // line end of the block's last line, exclusive of the trailing newline
  kind: BlockKind
}

/** The top-level block owning the line at `pos`, or null on a blank/unowned line (nothing to grab). */
export function blockAt(doc: string, pos: number): Block | null {
  const lines = doc.split('\n')
  const n = lines.length
  const starts = new Array<number>(n)
  const ends = new Array<number>(n)
  for (let p = 0, i = 0; i < n; i++) {
    starts[i] = p
    ends[i] = p + lines[i].length
    p = ends[i] + 1
  }

  // The line holding pos: the first whose end (pre-newline) is at/after pos.
  let li = n - 1
  for (let i = 0; i < n; i++) {
    if (pos <= ends[i]) {
      li = i
      break
    }
  }
  if (lines[li].trim() === '') return null

  const callout = calloutLines(lines)
  const fences = fencedCodeRanges(doc)
  const tables = tableRegions(doc)
  const inFence = (i: number): boolean => fences.some(([f, t]) => starts[i] >= f && starts[i] <= t)
  const inTable = (i: number): boolean => tables.some((r) => starts[i] >= r.from && starts[i] <= r.to)

  // List membership for the whole doc: marker lines PLUS their indented continuations (a wrapped item body),
  // but only where a run actually holds a marker — so a bare indented paragraph isn't swept in. A blank line
  // breaks a run, so blank-separated "loose" items split into separate list blocks (a V1 decision); a
  // multi-line item within a run stays whole.
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

  // 1. Callout box (a blockquote tagged `[!type]`) — the whole box, walking to its first/last member.
  if (callout[li]) {
    let a = li
    while (a > 0 && callout[a] && !callout[a]!.first) a--
    let b = li
    while (b < n - 1 && callout[b] && !callout[b]!.last) b++
    return { from: starts[a], to: ends[b], kind: 'callout' }
  }
  // 2. Plain blockquote — the contiguous `>` run that isn't a callout.
  if (isBlockquoteLine(lines[li])) {
    let a = li
    while (a > 0 && !callout[a - 1] && isBlockquoteLine(lines[a - 1])) a--
    let b = li
    while (b < n - 1 && !callout[b + 1] && isBlockquoteLine(lines[b + 1])) b++
    return { from: starts[a], to: ends[b], kind: 'blockquote' }
  }
  // 3. Fenced code — before heading/list so a `#`/`-` line inside the fence isn't mis-read.
  if (inFence(li)) {
    const f = fences.find(([ff, tt]) => starts[li] >= ff && starts[li] <= tt)!
    return { from: f[0], to: f[1], kind: 'code' }
  }
  // 4. Table region (the GFM source the widget renders over).
  if (inTable(li)) {
    const r = tables.find((rr) => starts[li] >= rr.from && starts[li] <= rr.to)!
    return { from: r.from, to: r.to, kind: 'table' }
  }
  // 5. Heading + its whole section (to the next equal/higher heading); a body-less heading is one line.
  if (isHeadingLine(lines[li])) {
    const sec = headingSections(doc).find((s) => s.from === starts[li])
    return sec ? { from: sec.from, to: sec.to, kind: 'heading' } : { from: starts[li], to: ends[li], kind: 'heading' }
  }
  // 6. List — the whole run of marker + continuation lines, so a wrapped item body stays with its item.
  if (listMember[li]) {
    let a = li
    while (a > 0 && listMember[a - 1]) a--
    let b = li
    while (b < n - 1 && listMember[b + 1]) b++
    return { from: starts[a], to: ends[b], kind: 'list' }
  }
  // 7. Thematic break — a single-line block (recognized so a paragraph can't absorb it).
  if (isThematicBreakLine(lines[li])) return { from: starts[li], to: ends[li], kind: 'hr' }

  // 8. Paragraph — the run of non-blank lines claimed by NO other kind, bounded by a blank or any block.
  const claimed = (i: number): boolean =>
    lines[i].trim() === '' ||
    !!callout[i] ||
    isBlockquoteLine(lines[i]) ||
    inFence(i) ||
    inTable(i) ||
    isHeadingLine(lines[i]) ||
    listMember[i] ||
    isThematicBreakLine(lines[i])
  let a = li
  while (a > 0 && !claimed(a - 1)) a--
  let b = li
  while (b < n - 1 && !claimed(b + 1)) b++
  return { from: starts[a], to: ends[b], kind: 'paragraph' }
}
