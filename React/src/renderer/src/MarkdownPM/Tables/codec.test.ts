import { describe, it, expect } from 'vitest'
import { parseTable, serialize, splitRow, parseDelimiter } from './codec'

describe('codec', () => {
  it('splitRow splits on unescaped pipes, keeps \\| in-cell, records pipe offsets', () => {
    const r = splitRow('| a\\|b | c |', 0)
    expect(r.cells.map((c) => c.text)).toEqual(['a\\|b', 'c'])
    expect(r.pipes).toEqual([0, 7, 11]) // leading, middle, trailing structural pipes
  })

  it('splitRow handles rows with no outer pipes', () => {
    const r = splitRow('a | b', 0)
    expect(r.cells.map((c) => c.text)).toEqual(['a', 'b'])
  })

  it('parseDelimiter reads dashes + alignment', () => {
    expect(parseDelimiter('|:--|--:|:-:|')).toEqual([
      { align: 'left', dashes: 2 },
      { align: 'right', dashes: 2 },
      { align: 'center', dashes: 1 }
    ])
  })

  it('parseTable returns null on a non-table and on a code-broken pipe', () => {
    expect(parseTable('not a table')).toBeNull()
    expect(parseTable('| `a|b` | c |\n|---|---|')).toBeNull()
  })

  it('round-trips canonical GFM with widths + alignment', () => {
    const src = '| a | b |\n| :--- | ---: |\n| 1 | 2 |'
    const m = parseTable(src)!
    expect(m.columns).toEqual([
      { align: 'left', dashes: 3 },
      { align: 'right', dashes: 3 }
    ])
    expect(m.header).toEqual(['a', 'b'])
    expect(m.rows).toEqual([['1', '2']])
    expect(serialize(m)).toBe(src)
  })
})
