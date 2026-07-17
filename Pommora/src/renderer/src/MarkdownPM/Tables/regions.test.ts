import { describe, it, expect } from 'vitest'
import { tableRegions, modelFromRegion } from './regions'
import { parseTable } from './codec'

describe('regions', () => {
  it('finds a top-level table and its row/pipe geometry; excludes the delimiter from rows', () => {
    const doc = 'intro\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nafter'
    const [r] = tableRegions(doc)
    expect(r.rows.length).toBe(2) // header + 1 body
    expect(r.delimiter.columns.length).toBe(2)
    expect(doc.slice(r.from, r.to)).toBe('| a | b |\n|---|---|\n| 1 | 2 |')
  })

  it('skips a pipe table inside a fenced code block', () => {
    const doc = '```\n| a | b |\n|---|---|\n```'
    expect(tableRegions(doc)).toEqual([])
  })

  it('skips a half-typed table (no delimiter yet)', () => {
    expect(tableRegions('| a | b |\nnot a delimiter')).toEqual([])
  })

  it('modelFromRegion equals parseTable on the same slice (the widget skips the second parse)', () => {
    for (const table of [
      '| a | b |\n|---|---|\n| 1 | 2 |',
      '| h1 | h2 | h3 |\n| :--- | :-: | ---: |\n| 1 | 2 | 3 |\n| 4 | 5 | 6 |',
      '| a\\|b | c |\n| ---- | -- |\n| x | y |', // escaped pipe + uneven dash widths
      '| only header |\n| --- |', // header-only, no body rows
    ]) {
      const [r] = tableRegions(table)
      expect(modelFromRegion(r)).toEqual(parseTable(table))
    }
  })
})
