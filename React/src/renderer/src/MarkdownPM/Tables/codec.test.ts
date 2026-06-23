import { describe, it, expect } from 'vitest'
import {
  parseTable,
  serialize,
  splitRow,
  parseDelimiter,
  escapeCell,
  unescapeCell,
  cellToSource,
  cellToDisplay
} from './codec'

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

  it('splitRow: a pipe after an escaped backslash (\\\\|) is structural, not escaped', () => {
    // '| a \\| b |' — the \\ is an escaped backslash, so the following | IS a real cell boundary → 2 cells
    expect(splitRow('| a \\\\| b |', 0).cells.length).toBe(2)
  })

  it('splitRow returns full inter-pipe segments (untrimmed) — one flex item per cell', () => {
    expect(splitRow('| a | b |', 0).segments).toEqual([
      [1, 4], // ' a ' incl. padding
      [5, 8] // ' b ' incl. padding
    ])
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

  it('escapeCell / unescapeCell are inverse for backslashes and pipes', () => {
    for (const s of ['a|b', 'a\\b', 'a\\|b', 'plain', '|||', '\\\\', 'C:\\path']) {
      expect(unescapeCell(escapeCell(s))).toBe(s)
    }
    expect(escapeCell('a|b')).toBe('a\\|b') // a literal pipe escapes
    expect(escapeCell('a\\|b')).toBe('a\\\\\\|b') // a literal backslash AND pipe both escape
  })

  it('cellToSource / cellToDisplay round-trip in-cell newlines as <br> (and still escape pipes)', () => {
    expect(cellToSource('a\nb')).toBe('a<br>b') // newline → <br> so the row never splits
    expect(cellToSource('a|b\nc')).toBe('a\\|b<br>c') // pipe escaped AND newline serialized
    expect(cellToDisplay('a<br>b')).toBe('a\nb') // <br> → newline for the multi-line cell editor
    for (const s of ['a\nb', 'a|b', 'line1\nline2|x', 'plain', 'a\nb\nc'])
      expect(cellToDisplay(cellToSource(s))).toBe(s) // full display→source→display round-trip
  })

  it('parseTable keeps raw escaped cell text; unescapeCell renders the literal for display', () => {
    const m = parseTable('| a\\|b | c |\n| --- | --- |')!
    expect(m.header[0]).toBe('a\\|b') // raw source form (matches splitRow contract)
    expect(unescapeCell(m.header[0])).toBe('a|b') // display form — the backslash is gone
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
