import { Annotation } from '@codemirror/state'
import { parseTable, serialize } from './codec'
import { setCell } from './operations'
import { tableRegions } from './regions'

// Marks a transaction as the table widget editing its own source. The widget StateField remaps its
// decorations (keeping the widget + its focused cell editor mounted) instead of rebuilding from the doc;
// external edits carry no annotation, so they rebuild. This is what keeps cell focus across an edit.
export const tableSelfEdit = Annotation.define<boolean>()

// Apply one cell edit to a table's GFM text, returning canonical GFM (dash-widths + alignment preserved).
// Visual-row convention: row 0 = header, row >= 1 = body[row-1]. If the text doesn't parse as a table it
// is returned unchanged — the caller only passes a detected region, so this is just a safety floor.
// (Used for whole-table normalization; live cell edits use cellCommitChange for a minimal, focus-safe diff.)
export function applyCellEdit(regionText: string, row: number, col: number, text: string): string {
  const m = parseTable(regionText)
  if (!m) return regionText
  return serialize(setCell(m, row, col, text))
}

// Minimal-diff cell edit: replace ONLY the cell's source span (not the whole table) so the block
// decoration remaps cleanly via deco.map and the focused cell editor never remounts. Pipes are escaped.
// Returns null if the table or cell is out of range. row 0 = header, row >= 1 = body[row-1].
export function cellCommitChange(
  docText: string,
  tableIndex: number,
  row: number,
  col: number,
  newText: string
): { from: number; to: number; insert: string } | null {
  const seg = tableRegions(docText)[tableIndex]?.rows[row]?.segments[col]
  if (!seg) return null
  return { from: seg[0], to: seg[1], insert: ` ${newText.replace(/\|/g, '\\|')} ` }
}
