import { describe, it, expect } from 'vitest'
import { nextCell } from './navigate'

// Visual-row convention: row 0 = header, rows 1..totalRows-1 = body. totalRows counts the header.
// A 2-column, 3-visual-row table (header + 2 body) → totalRows = 3, cols = 2.
describe('nextCell — cell-to-cell navigation', () => {
  it('Tab moves right, then wraps to the start of the next row', () => {
    expect(nextCell(3, 2, 0, 0, 'next')).toEqual({ row: 0, col: 1 })
    expect(nextCell(3, 2, 0, 1, 'next')).toEqual({ row: 1, col: 0 })
  })

  it('Tab past the last cell exits after the table', () => {
    expect(nextCell(3, 2, 2, 1, 'next')).toBe('after')
  })

  it('Shift-Tab moves left, then wraps to the end of the previous row', () => {
    expect(nextCell(3, 2, 1, 0, 'prev')).toEqual({ row: 0, col: 1 })
    expect(nextCell(3, 2, 0, 1, 'prev')).toEqual({ row: 0, col: 0 })
  })

  it('Shift-Tab before the first cell exits before the table', () => {
    expect(nextCell(3, 2, 0, 0, 'prev')).toBe('before')
  })

  it('Enter moves to the cell below, then exits after the last row', () => {
    expect(nextCell(3, 2, 0, 1, 'down')).toEqual({ row: 1, col: 1 })
    expect(nextCell(3, 2, 2, 1, 'down')).toBe('after')
  })
})
