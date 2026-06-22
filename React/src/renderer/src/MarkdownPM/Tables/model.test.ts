import { describe, it, expect } from 'vitest'
import { emptyTable, normalize } from './model'

describe('model', () => {
  it('emptyTable builds an N×M rectangular model with equal default dashes', () => {
    const m = emptyTable(3, 3)
    expect(m.columns.map((c) => c.dashes)).toEqual([6, 6, 6]) // seeded magnitude, total ≥ ~18
    expect(m.columns.every((c) => c.align === null)).toBe(true)
    expect(m.header).toEqual(['', '', ''])
    expect(m.rows).toEqual([
      ['', '', ''],
      ['', '', '']
    ]) // 3 rows total incl. header → 2 body
  })

  it('normalize pads short rows and truncates long rows to column count', () => {
    const m = normalize({
      columns: [
        { align: null, dashes: 3 },
        { align: null, dashes: 3 }
      ],
      header: ['a'],
      rows: [['x', 'y', 'z']]
    })
    expect(m.header).toEqual(['a', ''])
    expect(m.rows).toEqual([['x', 'y']])
  })
})
