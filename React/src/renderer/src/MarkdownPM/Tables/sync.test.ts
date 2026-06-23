import { describe, it, expect } from 'vitest'
import { cellCommitChange } from './sync'
import { parseTable, unescapeCell } from './codec'

describe('cellCommitChange — minimal-diff cell edit (replace just the cell span, focus-safe)', () => {
  const doc = '| a | b |\n| --- | --- |\n| 1 | 2 |'
  const splice = (c: { from: number; to: number; insert: string }): string =>
    doc.slice(0, c.from) + c.insert + doc.slice(c.to)

  it('replaces a body cell span (row 1 = first body); re-parse reflects the edit', () => {
    expect(parseTable(splice(cellCommitChange(doc, 0, 1, 0, 'X')!))!.rows).toEqual([['X', '2']])
  })

  it('replaces a header cell span (row 0)', () => {
    expect(parseTable(splice(cellCommitChange(doc, 0, 0, 1, 'B!')!))!.header).toEqual(['a', 'B!'])
  })

  it('escapes pipes in the inserted text', () => {
    expect(cellCommitChange(doc, 0, 0, 0, 'x|y')!.insert).toContain('\\|')
  })

  it('only touches the one cell — the change span is strictly inside the table region', () => {
    const c = cellCommitChange(doc, 0, 1, 0, 'X')!
    expect(c.from).toBeGreaterThan(0)
    expect(c.to).toBeLessThan(doc.length)
  })

  it('returns null for an out-of-range cell or table index', () => {
    expect(cellCommitChange(doc, 0, 9, 9, 'z')).toBeNull()
    expect(cellCommitChange(doc, 5, 0, 0, 'z')).toBeNull()
  })

  it('serializes in-cell newlines as <br> so the row stays single-line (multi-line cell)', () => {
    const c = cellCommitChange(doc, 0, 1, 0, 'x\ny')!
    expect(c.insert).toBe(' x<br>y ')
    expect(c.insert).not.toContain('\n')
  })

  it('escapes backslash+pipe so a literal `a\\|b` stays ONE cell and round-trips', () => {
    const c = cellCommitChange(doc, 0, 0, 1, 'a\\|b')! // user typed: a \ | b into header col 1
    const spliced = doc.slice(0, c.from) + c.insert + doc.slice(c.to)
    const m = parseTable(spliced)!
    expect(m.header).toHaveLength(2) // structure intact — no phantom column
    expect(unescapeCell(m.header[1])).toBe('a\\|b') // value preserved through the round-trip
  })
})
