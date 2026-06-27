// Pure source-line logic for list drag-to-reorder. No CM6 / DOM here — the extension (`listDrag.ts`)
// owns the gesture + overlay and calls these to turn a grab + drop into a single `changes` array.
// Everything operates on the doc string + offsets so it's unit-testable without an editor.
import { parseListMarkerPrefixed as parseListMarker, quoteDepth } from '../detect'
import { lineStartAt, lineEndAt } from '../input'

export interface ChangeSpec {
  from: number
  to: number
  insert: string
}

/** The `[ ]`↔`[x]` toggle change for a checkbox glyph CLICK at `pos`, or null when the line under `pos`
 *  isn't a checkbox. Shared by the extension's click handler so press-to-drag never flips the box. */
export function checkboxToggleChange(doc: string, pos: number): ChangeSpec | null {
  const ls = lineStartAt(doc, pos)
  const lm = parseListMarker(doc.slice(ls, lineEndAt(doc, pos)))
  if (lm?.kind !== 'checkbox' || !lm.box) return null
  return { from: ls + lm.box.start, to: ls + lm.box.end, insert: lm.checked ? '[ ]' : '[x]' }
}

/** The list line under `pos` plus all following deeper-indented lines (its nested descendants). */
export interface SubBlock {
  from: number // line start of the grabbed item
  to: number // line end of the last descendant (exclusive of the trailing newline)
  level: number
}

/** Resolve the contiguous sub-block owned by the list item whose line contains `pos`.
 *  Returns null when `pos` isn't on a list line. */
export function subBlockAt(doc: string, pos: number): SubBlock | null {
  const from = lineStartAt(doc, pos)
  const headEnd = lineEndAt(doc, from)
  const head = parseListMarker(doc.slice(from, headEnd))
  if (head === null) return null
  const headDepth = quoteDepth(doc.slice(from, headEnd))

  let to = headEnd
  for (let p = headEnd; p < doc.length; ) {
    const fs = p + 1 // skip the '\n'
    const fe = lineEndAt(doc, fs)
    const fline = doc.slice(fs, fe)
    const lm = parseListMarker(fline)
    // A descendant must be deeper AND at the same quote depth — a different `>` depth is a different box, never a child.
    if (lm === null || lm.level <= head.level || quoteDepth(fline) !== headDepth) break
    to = fe
    p = fe
  }
  return { from, to, level: head.level }
}

/** A drop slot: insert the moved block so it starts at `at` (a line-start offset in the ORIGINAL doc). */
export interface Slot {
  at: number
  indent?: string // when set, the moved block is re-indented so its head sits at this depth (re-nesting)
}

// A line's full lead: leading indent + the blockquote/callout `>` prefix + list-indent whitespace. The drop
// "indent" a block adopts is the target's lead, so dragging in/out of a callout re-prefixes correctly (no
// doubled `>`). Leading `[ \t]*` first so an indented `  > - x` strips its `>` too.
const LEAD_RE = /^[ \t]*(?:>[ \t]?)*[ \t]*/

/** Re-indent a block so its head line sits at `targetIndent`, shifting every descendant by the same delta
 *  (relative nesting preserved). Strips the head's lead by LENGTH off each line's own lead (prefix + indent),
 *  so it can't silently skip a descendant that mixes tabs/spaces. Verbatim when targetIndent is undefined. */
function reindentBlock(blockText: string, targetIndent: string | undefined): string {
  if (targetIndent === undefined) return blockText
  const headLen = (blockText.match(LEAD_RE)?.[0] ?? '').length
  return blockText
    .split('\n')
    .map((line) => {
      const ws = line.match(LEAD_RE)?.[0] ?? ''
      return targetIndent + ws.slice(Math.min(headLen, ws.length)) + line.slice(ws.length)
    })
    .join('\n')
}

/** Move `block` to start at `slot.at`, expressed as two changes (delete source, insert at target) over
 *  the original doc. The block is re-indented to `slot.indent` (re-nesting) — verbatim when unset. Newlines
 *  are handled so the moved block keeps its own line and never fuses with a neighbor. Null for a no-op. */
function moveBlockChanges(doc: string, block: SubBlock, slot: Slot): ChangeSpec[] | null {
  const blockText = reindentBlock(doc.slice(block.from, block.to), slot.indent)
  // Cut the block plus one adjoining newline so no blank line is orphaned: its trailing newline if it has
  // one, otherwise the preceding newline (an EOF block has no trailing newline of its own).
  const atEof = block.to >= doc.length
  const cutFrom = atEof && block.from > 0 ? block.from - 1 : block.from
  const cutTo = atEof ? doc.length : block.to + 1

  if (slot.at >= cutFrom && slot.at <= cutTo) return null // dropping inside itself → no-op

  const cut: ChangeSpec = { from: cutFrom, to: cutTo, insert: '' }

  // Dropping at EOF: prepend a separating newline (if the doc doesn't end in one), drop the block's own.
  if (slot.at >= doc.length) {
    return [cut, { from: doc.length, to: doc.length, insert: (doc.endsWith('\n') ? '' : '\n') + blockText }]
  }
  // Mid-doc: the block lands at a line-start `slot.at`, keeping its own line via a trailing newline.
  return [cut, { from: slot.at, to: slot.at, insert: `${blockText}\n` }]
}

/** Renumber the ordered run that the line at `pos` belongs to, sequentially from the run's first number.
 *  A "run" is a maximal block of consecutive same-indent ordered lines. Returns per-marker rewrites
 *  (only the lines whose printed number changes), as changes over `doc`. */
export function renumberOrderedRun(doc: string, pos: number): ChangeSpec[] {
  if (pos < 0 || pos > doc.length) return []
  const ls = lineStartAt(doc, pos)
  const lm = parseListMarker(doc.slice(ls, lineEndAt(doc, pos)))
  if (lm === null || lm.kind !== 'ordered') return []
  const indent = doc.slice(ls, ls + lm.markerStart)

  // Walk up to the first line of the run (same indent, ordered, contiguous).
  let runStart = ls
  while (runStart > 0) {
    const prevEnd = runStart - 1
    const prevStart = lineStartAt(doc, prevEnd)
    const plm = parseListMarker(doc.slice(prevStart, prevEnd))
    if (plm === null || plm.kind !== 'ordered' || doc.slice(prevStart, prevStart + plm.markerStart) !== indent) break
    runStart = prevStart
  }

  // Collect the run's lines, then renumber from its SMALLEST present digit. A sequential run's minimum is
  // its original start, and a move only permutes the digits — so this preserves a list that began at 5 as
  // 5,6,7 while still snapping a 1-based list back to 1,2,3 after the moved item carried its old number in.
  type Row = { digitFrom: number; digits: string }
  const rows: Row[] = []
  for (let p = runStart; p < doc.length; ) {
    const le = lineEndAt(doc, p)
    const rlm = parseListMarker(doc.slice(p, le))
    if (rlm === null || rlm.kind !== 'ordered' || doc.slice(p, p + rlm.markerStart) !== indent) break
    rows.push({ digitFrom: p + rlm.markerStart, digits: rlm.digits ?? '0' })
    p = le + 1
  }
  const start = Math.min(...rows.map((r) => parseInt(r.digits, 10)))
  const changes: ChangeSpec[] = []
  rows.forEach((r, i) => {
    const want = String(start + i)
    if (r.digits !== want) changes.push({ from: r.digitFrom, to: r.digitFrom + r.digits.length, insert: want })
  })
  return changes
}

/** The full drop transaction: move the block, then renumber the ordered runs touched at both the source
 *  (where the block was) and the destination. Both renumber passes run against the POST-MOVE doc so the
 *  digit offsets are correct; all edits are returned mapped back onto the original doc as one batch. */
export function dropChanges(doc: string, block: SubBlock, slot: Slot): ChangeSpec[] | null {
  const move = moveBlockChanges(doc, block, slot)
  if (move === null) return null

  // Apply the move to a scratch string so renumber sees final offsets, then diff the whole result back.
  const moved = applyChanges(doc, move)

  // The insert change carries the block; its `from`, mapped through the prior cut, is the block's new
  // start in `moved` — that's the destination anchor for the renumber pass.
  const [cut, ins] = move
  const cutLen = cut.to - cut.from
  const destAnchor = ins.from > cut.from ? ins.from - cutLen : ins.from
  // Source anchor: the line that now sits where the block used to start (the block was removed).
  const sourceAnchor = Math.min(block.from, moved.length)

  const renumber = [...renumberOrderedRun(moved, sourceAnchor), ...renumberOrderedRun(moved, destAnchor)]
  // renumber edits are in moved-doc coordinates → recompute the whole result and emit ONE replace span.
  const finalDoc = applyChanges(moved, dedupeChanges(renumber))
  return diffAsSingleReplace(doc, finalDoc)
}

// Source + dest renumber passes can both touch the same run (small docs) → drop duplicate digit edits at
// the same offset so applyChanges doesn't double-write.
function dedupeChanges(changes: ChangeSpec[]): ChangeSpec[] {
  const seen = new Set<number>()
  const out: ChangeSpec[] = []
  for (const c of changes) {
    if (seen.has(c.from)) continue
    seen.add(c.from)
    out.push(c)
  }
  return out
}

/** Apply non-overlapping changes (sorted by `from`) to a string. */
export function applyChanges(doc: string, changes: ChangeSpec[]): string {
  const sorted = [...changes].sort((a, b) => a.from - b.from)
  let out = ''
  let cursor = 0
  for (const c of sorted) {
    out += doc.slice(cursor, c.from) + c.insert
    cursor = c.to
  }
  return out + doc.slice(cursor)
}

/** Collapse two strings into a single minimal `from/to/insert` replace (shared common prefix + suffix). */
function diffAsSingleReplace(a: string, b: string): ChangeSpec[] {
  if (a === b) return []
  let pre = 0
  const max = Math.min(a.length, b.length)
  while (pre < max && a[pre] === b[pre]) pre++
  let suf = 0
  while (suf < max - pre && a[a.length - 1 - suf] === b[b.length - 1 - suf]) suf++
  return [{ from: pre, to: a.length - suf, insert: b.slice(pre, b.length - suf) }]
}
