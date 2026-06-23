import { parseTable, serialize } from './codec'
import { setCell } from './operations'

// Apply one cell edit to a table's GFM text, returning canonical GFM (dash-widths + alignment preserved).
// Visual-row convention: row 0 = header, row >= 1 = body[row-1]. If the text doesn't parse as a table it
// is returned unchanged — the caller only passes a detected region, so this is just a safety floor.
export function applyCellEdit(regionText: string, row: number, col: number, text: string): string {
  const m = parseTable(regionText)
  if (!m) return regionText
  return serialize(setCell(m, row, col, text))
}
