export type NavDir = 'next' | 'prev' | 'down'
export type NavTarget = { row: number; col: number } | 'before' | 'after'

// Pure cell-to-cell navigation. Visual-row convention: row 0 = header, rows 1..totalRows-1 = body.
// 'next' = Tab, 'prev' = Shift-Tab, 'down' = Enter. Returns the target cell, or 'before'/'after' to exit
// past the table edge.
export function nextCell(
  totalRows: number,
  cols: number,
  row: number,
  col: number,
  dir: NavDir
): NavTarget {
  if (dir === 'next') {
    if (col + 1 < cols) return { row, col: col + 1 }
    if (row + 1 < totalRows) return { row: row + 1, col: 0 }
    return 'after'
  }
  if (dir === 'prev') {
    if (col > 0) return { row, col: col - 1 }
    if (row > 0) return { row: row - 1, col: cols - 1 }
    return 'before'
  }
  // 'down'
  if (row + 1 < totalRows) return { row: row + 1, col }
  return 'after'
}
