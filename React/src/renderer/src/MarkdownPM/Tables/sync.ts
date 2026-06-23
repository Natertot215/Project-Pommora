import { Annotation } from '@codemirror/state'
import { tableRegions } from './regions'
import { cellToSource } from './codec'

// Marks a transaction as the table widget editing its own source. The widget StateField remaps its
// decorations (keeping the widget + its focused cell editor mounted) instead of rebuilding from the doc;
// external edits carry no annotation, so they rebuild. This is what keeps cell focus across an edit.
export const tableSelfEdit = Annotation.define<boolean>()

// Minimal-diff cell edit: replace ONLY the cell's source span (not the whole table) so the block
// decoration remaps cleanly via deco.map and the focused cell editor never remounts. `cellToSource`
// escapes backslashes + pipes and serializes in-cell newlines as `<br>`, so the row stays single-line
// GFM no matter what's typed/pasted. Returns null if out of range. row 0 = header, row >= 1 = body[row-1].
export function cellCommitChange(
  docText: string,
  tableIndex: number,
  row: number,
  col: number,
  newText: string
): { from: number; to: number; insert: string } | null {
  const seg = tableRegions(docText)[tableIndex]?.rows[row]?.segments[col]
  if (!seg) return null
  return { from: seg[0], to: seg[1], insert: ` ${cellToSource(newText)} ` }
}
