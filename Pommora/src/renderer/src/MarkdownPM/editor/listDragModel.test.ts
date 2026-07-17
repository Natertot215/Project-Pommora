import { describe, it, expect } from 'vitest'
import {
  subBlockAt,
  dropChanges,
  applyChanges,
  blockMoveChanges,
  renumberOrderedRun,
  checkboxToggleChange,
  type Slot,
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

describe('drag inside a callout (prefix-aware)', () => {
  it('reorders a callout bullet without doubling the `>` prefix', () => {
    const doc = '> [!callout] head\n> - one\n> - two'
    const block = subBlockAt(doc, doc.indexOf('one'))!
    const changes = dropChanges(doc, block, { at: doc.length, indent: '> ' })!
    expect(applyChanges(doc, changes)).toBe('> [!callout] head\n> - two\n> - one')
  })
  it('subBlockAt does NOT swallow a top-level indented sibling across the box boundary', () => {
    const doc = '> - a\n\t- x' // a callout/quote bullet then a top-level nested bullet
    const block = subBlockAt(doc, doc.indexOf('a'))!
    expect(block.to).toBe(doc.indexOf('\n')) // block is just `> - a`, not the `\t- x` line
  })
  it('subBlockAt DOES keep a same-box deeper child', () => {
    const doc = '> - a\n> \t- child'
    const block = subBlockAt(doc, doc.indexOf('a'))!
    expect(block.to).toBe(doc.length) // the `> \t- child` shares the `>` box → captured
  })
})

describe('blockMoveChanges (blank-separated block move)', () => {
  const apply = (doc: string, range: { from: number; to: number }, at: number): string | null => {
    const c = blockMoveChanges(doc, range, { at })
    return c ? applyChanges(doc, c) : null
  }

  it('moves a block to EOF without double-blanking the source or gluing the target', () => {
    const doc = 'A\n\nB\n\nC'
    expect(apply(doc, { from: 3, to: 4 }, doc.length)).toBe('A\n\nC\n\nB')
  })

  it('moves a multi-line block cleanly (the reviewer-flagged case)', () => {
    const doc = 'A\n\nB1\nB2\nB3\n\nC'
    expect(apply(doc, { from: 3, to: 11 }, doc.length)).toBe('A\n\nC\n\nB1\nB2\nB3')
  })

  it('moves a block to the top of the document', () => {
    const doc = 'A\n\nB\n\nC'
    expect(apply(doc, { from: 6, to: 7 }, 0)).toBe('C\n\nA\n\nB')
  })

  it('moves a block between two others', () => {
    const doc = 'A\n\nB\n\nC\n\nD'
    expect(apply(doc, { from: 3, to: 4 }, doc.indexOf('D'))).toBe('A\n\nC\n\nB\n\nD')
  })

  it('returns null when dropping a block onto its own start', () => {
    expect(blockMoveChanges('A\n\nB\n\nC', { from: 3, to: 4 }, { at: 3 })).toBeNull()
  })

  it('preserves a trailing newline and does not double-blank on a move to EOF', () => {
    const doc = 'A\n\nB\n\nC\n'
    expect(apply(doc, { from: 0, to: 1 }, doc.length)).toBe('B\n\nC\n\nA\n')
  })

  it('snaps a blank-line drop target to the next content block', () => {
    const doc = 'A\n\nB\n\nC' // at=5 is the blank line between B and C → land cleanly before C
    expect(apply(doc, { from: 0, to: 1 }, 5)).toBe('B\n\nA\n\nC')
  })

  it('returns null when dropping onto its own preceding blank', () => {
    expect(blockMoveChanges('A\n\nB\n\nC', { from: 3, to: 4 }, { at: 2 })).toBeNull()
  })

  it('injects a blank separator when moving within a doc that had none', () => {
    expect(apply('A\nB\nC', { from: 0, to: 1 }, 5)).toBe('B\nC\n\nA')
  })

  it('a single-block doc has no valid target', () => {
    expect(blockMoveChanges('only', { from: 0, to: 4 }, { at: 0 })).toBeNull()
    expect(blockMoveChanges('only', { from: 0, to: 4 }, { at: 4 })).toBeNull()
  })

  // A glue-adjacent seam (two blockStarts-distinct blocks with no blank between) must not fuse on a drop —
  // blockStarts splits these into separate grips, so the move has to re-blank-separate both new seams.
  it('does not lazily-continue a list when a block drops under it (no blank below the list)', () => {
    const doc = '- a\n- b\npara X\n\nmover'
    expect(apply(doc, { from: doc.indexOf('mover'), to: doc.length }, doc.indexOf('para X'))).toBe(
      '- a\n- b\n\nmover\n\npara X',
    )
  })

  it('does not merge two paragraphs when a block drops between glued blocks', () => {
    const doc = 'head para\n- list item\n\nmover'
    expect(
      apply(doc, { from: doc.indexOf('mover'), to: doc.length }, doc.indexOf('- list item')),
    ).toBe('head para\n\nmover\n\n- list item')
  })

  it('heals the hole so moving a block out from between two glued blocks does not fuse them', () => {
    const doc = 'alpha\n- a\n- b\n\nbeta'
    expect(apply(doc, { from: doc.indexOf('- a'), to: doc.indexOf('- b') + 3 }, doc.length)).toBe(
      'alpha\n\nbeta\n\n- a\n- b',
    )
  })

  it('does not double-blank when the source ends in a trailing blank line', () => {
    const doc = 'A\n\nB\n\n'
    expect(apply(doc, { from: 0, to: 1 }, doc.length)).toBe('B\n\nA\n')
  })
})
