import { describe, it, expect } from 'vitest'
import { applyCellEdit } from './sync'
import { parseTable } from './codec'

describe('applyCellEdit — the cell-edit round-trip (parse → setCell → serialize, keeps GFM canonical)', () => {
  it('rewrites one body cell with the structure intact', () => {
    const m = parseTable(applyCellEdit('| a | b |\n| --- | --- |\n| 1 | 2 |', 1, 0, 'X'))!
    expect(m.header).toEqual(['a', 'b'])
    expect(m.rows).toEqual([['X', '2']])
  })

  it('edits the header (row 0) and preserves per-column alignment', () => {
    const m = parseTable(applyCellEdit('| a | b |\n| :--- | ---: |\n| 1 | 2 |', 0, 0, 'Header'))!
    expect(m.header).toEqual(['Header', 'b'])
    expect(m.columns[0].align).toBe('left')
    expect(m.columns[1].align).toBe('right')
  })

  it('returns the input unchanged when it does not parse as a table', () => {
    expect(applyCellEdit('not a table', 0, 0, 'x')).toBe('not a table')
  })
})
