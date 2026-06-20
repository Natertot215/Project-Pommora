import { describe, it, expect } from 'vitest'
import {
  continueListOnEnter,
  smartBackspace,
  canonicalizeCheckbox,
  autoPair,
  autoDelete,
  bracketSkipOnEnter,
  dashArrow,
  type Edit
} from './index'

/** Apply an Edit to a doc → the resulting string (for readable assertions). */
const apply = (doc: string, e: Edit): string => doc.slice(0, e.from) + e.insert + doc.slice(e.to)

describe('list continuation (Enter)', () => {
  it('continues a bullet, preserving indent', () => {
    const doc = '  - item'
    const e = continueListOnEnter(doc, doc.length, doc.length)!
    expect(apply(doc, e)).toBe('  - item\n  - ')
  })
  it('increments an ordered marker', () => {
    const doc = '1. a'
    const e = continueListOnEnter(doc, doc.length, doc.length)!
    expect(apply(doc, e)).toBe('1. a\n2. ')
  })
  it('continues a checkbox as a fresh unchecked box', () => {
    const doc = '- [x] done'
    const e = continueListOnEnter(doc, doc.length, doc.length)!
    expect(apply(doc, e)).toBe('- [x] done\n- [ ] ')
  })
  it('does not fire on a non-list line', () => {
    expect(continueListOnEnter('plain', 5, 5)).toBeNull()
  })
})

describe('smart backspace (whole marker, all markers)', () => {
  const atContentStart = (doc: string, marker: string): Edit | null => {
    const cs = doc.indexOf(marker) + marker.length
    return smartBackspace(doc, cs, cs)
  }
  it('deletes a checkbox marker, caret to line start', () => {
    const doc = '- [ ] task'
    const e = atContentStart(doc, '- [ ] ')!
    expect(apply(doc, e)).toBe('task')
    expect(e.selection).toBe(0)
  })
  it('deletes bullet / ordered / blockquote / heading markers', () => {
    expect(apply('- x', atContentStart('- x', '- ')!)).toBe('x')
    expect(apply('1. x', atContentStart('1. x', '1. ')!)).toBe('x')
    expect(apply('> x', atContentStart('> x', '> ')!)).toBe('x')
    expect(apply('## x', atContentStart('## x', '## ')!)).toBe('x')
  })
  it('only fires at content-start, not mid-content', () => {
    expect(smartBackspace('- abc', 4, 4)).toBeNull()
  })
})

describe('checkbox canonicalization', () => {
  it('-[] + space → "- [ ] " with caret after', () => {
    const doc = '-[]'
    const e = canonicalizeCheckbox(doc, 3, 3, ' ')!
    expect(apply(doc, e)).toBe('- [ ] ')
    expect(e.selection).toBe(6)
  })
  it('-[x] + space → "- [x] "', () => {
    const doc = '-[x]'
    expect(apply(doc, canonicalizeCheckbox(doc, 4, 4, ' ')!)).toBe('- [x] ')
  })
})

describe('auto-pair + auto-delete', () => {
  it('** completes to **|** (caret between the pairs)', () => {
    const e = autoPair('*', 1, 1, '*')! // existing *, typing the 2nd *
    expect(apply('*', e)).toBe('****') // ** open + ** close
    expect(e.selection).toBe(2) // caret between → **|**
  })
  it('single [ pairs at line start, not after a word char', () => {
    expect(autoPair('', 0, 0, '[')).not.toBeNull()
    expect(autoPair('-', 1, 1, '[')).toBeNull() // -[ flows for checkbox shorthand
  })
  it('backspace inside an empty pair deletes both halves', () => {
    const e = autoDelete('[]', 1, 1)!
    expect(apply('[]', e)).toBe('')
  })
})

describe('bracket-skip on Enter', () => {
  it('jumps past a single closer', () => {
    const e = bracketSkipOnEnter('[]', 1, 1)!
    expect(e.selection).toBe(2)
    expect(e.insert).toBe('')
  })
  it('double-jumps [[ | ]]', () => {
    const e = bracketSkipOnEnter('[[]]', 2, 2)!
    expect(e.selection).toBe(4)
  })
})

describe('dash + arrow auto-format', () => {
  it('-- then a letter → em-dash', () => {
    const doc = '--'
    const e = dashArrow(doc + '', 2, 2, 'a')!
    expect(apply('--', e)).toBe('—a')
  })
  it('preserves --- (HR)', () => {
    expect(dashArrow('--', 2, 2, '-')).toBeNull() // typing the 3rd dash
  })
  it('-> → → and <- → ←', () => {
    expect(apply('-', dashArrow('-', 1, 1, '>')!)).toBe('→')
    expect(apply('<', dashArrow('<', 1, 1, '-')!)).toBe('←')
  })
  it('spaced " - " second space → en-dash', () => {
    const doc = 'a -'
    expect(apply(doc, dashArrow(doc, 3, 3, ' ')!)).toBe('a – ')
  })
})
