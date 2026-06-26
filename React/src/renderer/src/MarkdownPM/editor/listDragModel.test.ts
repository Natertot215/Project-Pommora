import { describe, it, expect } from 'vitest'
import {
  subBlockAt,
  dropChanges,
  applyChanges,
  renumberOrderedRun,
  checkboxToggleChange,
  type Slot
} from './listDragModel'

/** Drop the item whose line contains `grab` so it starts at the line containing `dropLine` — returns the
 *  resulting doc string. `at` is resolved to the start of the line that contains `dropLine`. */
function drop(doc: string, grab: number, at: number): string {
  const block = subBlockAt(doc, grab)
  if (!block) throw new Error('grab not on a list line')
  const slot: Slot = { at }
  const changes = dropChanges(doc, block, slot)
  return changes ? applyChanges(doc, changes) : doc
}

const lineStart = (doc: string, needle: string): number => doc.indexOf(needle)

describe('subBlockAt', () => {
  it('returns just the line for a flat item', () => {
    const doc = '- a\n- b\n- c'
    const b = subBlockAt(doc, doc.indexOf('b'))!
    expect(doc.slice(b.from, b.to)).toBe('- b')
  })
  it('includes deeper-indented descendants', () => {
    const doc = '- a\n\t- a1\n\t- a2\n- b'
    const b = subBlockAt(doc, 1)!
    expect(doc.slice(b.from, b.to)).toBe('- a\n\t- a1\n\t- a2')
  })
  it('returns null off a list line', () => {
    expect(subBlockAt('plain text', 2)).toBe(null)
  })
})

describe('drag reorders source lines', () => {
  it('moves a bullet item down past a sibling', () => {
    const doc = '- a\n- b\n- c'
    // grab "a", drop after "b" → start of "c" line
    const out = drop(doc, lineStart(doc, 'a'), lineStart(doc, '- c'))
    expect(out).toBe('- b\n- a\n- c')
  })
  it('moves a bullet item to the end', () => {
    const doc = '- a\n- b\n- c'
    const out = drop(doc, lineStart(doc, 'a'), doc.length)
    expect(out).toBe('- b\n- c\n- a')
  })
})

describe('ordered list renumbers after a move', () => {
  it('renumbers source + destination runs', () => {
    const doc = '1. a\n2. b\n3. c'
    // grab "3. c", drop it at the very start (before "1. a")
    const out = drop(doc, lineStart(doc, 'c'), 0)
    expect(out).toBe('1. c\n2. a\n3. b')
  })
  it('renumbers when moving the first item down', () => {
    const doc = '1. a\n2. b\n3. c'
    const out = drop(doc, lineStart(doc, 'a'), doc.length)
    expect(out).toBe('1. b\n2. c\n3. a')
  })
})

describe('checkbox state preserved across a move', () => {
  it('keeps [x] / [ ] verbatim when reordering', () => {
    const doc = '- [x] done\n- [ ] todo\n- [x] also'
    const out = drop(doc, lineStart(doc, 'done'), doc.length)
    expect(out).toBe('- [ ] todo\n- [x] also\n- [x] done')
  })
})

describe('nested sub-block moves as a unit', () => {
  it('carries descendants with the parent', () => {
    const doc = '- a\n\t- a1\n\t- a2\n- b'
    // move "a" (+ a1, a2) to after "b"
    const out = drop(doc, lineStart(doc, '- a'), doc.length)
    expect(out).toBe('- b\n- a\n\t- a1\n\t- a2')
  })
})

describe('re-nesting on drop (slot.indent adopts the target depth)', () => {
  it('flattens a nested item to root when dropped at a root-indent target', () => {
    const doc = '- a\n\t- nested\n- b'
    const block = subBlockAt(doc, lineStart(doc, 'nested'))!
    const changes = dropChanges(doc, block, { at: doc.length, indent: '' })!
    expect(applyChanges(doc, changes)).toBe('- a\n- b\n- nested')
  })
  it('re-indents the whole sub-block, preserving relative nesting', () => {
    const doc = '- a\n\t- p\n\t\t- c\n- b'
    const block = subBlockAt(doc, lineStart(doc, '- p'))!
    const changes = dropChanges(doc, block, { at: doc.length, indent: '' })!
    expect(applyChanges(doc, changes)).toBe('- a\n- b\n- p\n\t- c')
  })
})

describe('click (no drag past threshold) toggles a checkbox, never reorders', () => {
  it('unchecked → checked toggle change targets the box only', () => {
    const doc = '- [ ] todo\n- [ ] next'
    const c = checkboxToggleChange(doc, doc.indexOf('[ ]'))!
    expect(applyChanges(doc, [c])).toBe('- [x] todo\n- [ ] next')
  })
  it('checked → unchecked', () => {
    const doc = '- [x] done'
    const c = checkboxToggleChange(doc, 2)!
    expect(applyChanges(doc, [c])).toBe('- [ ] done')
  })
  it('returns null for a bullet (no toggle) so a click just places the caret', () => {
    expect(checkboxToggleChange('- plain', 0)).toBe(null)
  })
})

describe('renumberOrderedRun', () => {
  it('produces minimal digit rewrites', () => {
    const doc = '3. a\n4. b\n5. c'
    const changes = renumberOrderedRun(doc, 0)
    expect(applyChanges(doc, changes)).toBe('3. a\n4. b\n5. c') // already sequential from its start
  })
  it('fixes a broken run', () => {
    const doc = '1. a\n1. b\n1. c'
    expect(applyChanges(doc, renumberOrderedRun(doc, 0))).toBe('1. a\n2. b\n3. c')
  })
})
