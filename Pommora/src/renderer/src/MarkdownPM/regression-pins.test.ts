// Pins for the adversarial-review fix wave — each case is an executed break from the MarkdownPM
// findings catalog, fixed and pinned so it can't quietly return. Grouped by the seam it guards.
import { describe, it, expect } from 'vitest'
import { isInsideCode } from './parser'
import { splitRow } from './Tables/codec'
import { tokenize } from './tokens'
import {
  autoPair,
  dashArrow,
  closeConstructOnEnter,
  continueListOnEnter,
  continueBlockquoteOnEnter,
  outdentListOnShiftTab,
} from './input'
import { setHeading, setList } from './input/format'
import { subBlockAt, renumberOrderedRun } from './editor/listDragModel'
import { calloutDeleteVerdict } from './editor/calloutGuard'
import { headingSections } from './editor/folding'
import { fencedCodeRanges } from './decorations/intent'

describe('isInsideCode — tilde fences + inline spans', () => {
  it('treats ~~~ fences as code', () => {
    const doc = '~~~\n# not a heading\n~~~'
    expect(isInsideCode(6, doc)).toBe(true)
  })
  it('pairs fences by marker char (a ~~~ line inside ``` is content)', () => {
    const doc = '```\n~~~\ncode\n```\nprose'
    expect(isInsideCode(9, doc)).toBe(true) // "code" — still inside the ``` fence
    expect(isInsideCode(18, doc)).toBe(false) // "prose"
  })
  it('counts inline spans — including unclosed ones being typed', () => {
    expect(isInsideCode(10, 'run `npm --x` now')).toBe(true) // inside the span
    expect(isInsideCode(16, 'run `npm install --')).toBe(true) // unclosed opener
    expect(isInsideCode(2, 'ab `c`')).toBe(false) // before the span
  })
  it('treats the closing backtick as a boundary so type-over still works', () => {
    expect(isInsideCode(5, '`code`')).toBe(false) // AT the closing marker
  })
})

describe('splitRow — escaped trailing pipe is a cell, not a row end', () => {
  it('keeps the last cell when the row ends in \\|', () => {
    const { cells } = splitRow('a | b\\|', 0)
    expect(cells.map((c) => c.text)).toEqual(['a', 'b\\|'])
  })
})

describe('tokenize — connections/links inside inline code are literal', () => {
  it('drops wikilinks and links overlapping a code span', () => {
    const kinds = tokenize('`see [[Page]] and [x](https://e.com)`').map((t) => t.kind)
    expect(kinds).toContain('inlineCode')
    expect(kinds).not.toContain('wikiLink')
    expect(kinds).not.toContain('link')
  })
})

describe('autoPair — doubled-marker branch', () => {
  it('does not stack when completing an existing bold', () => {
    expect(autoPair('**word*', 7, 7, '*')).toBeNull() // typed closer completes **word**
  })
  it('does not pair a doubled marker glued to a word', () => {
    expect(autoPair('snake_', 6, 6, '_')).toBeNull()
  })
  it('still promotes a fresh pair to the doubled form', () => {
    // `*|*` + `*` → `**|**` (consume the auto-inserted closer)
    expect(autoPair('**', 1, 1, '*')).toEqual({ from: 1, to: 1, insert: '**', selection: 2 })
  })
})

describe('dashArrow — content guards', () => {
  it('keeps -- literal inside URLs', () => {
    const doc = 'see https://ex--'
    expect(dashArrow(doc, doc.length, doc.length, 'a')).toBeNull()
  })
  it('keeps -- literal inside [[titles]] (em-dash would retarget the connection)', () => {
    const doc = '[[pages 5--'
    expect(dashArrow(doc, doc.length, doc.length, '7')).toBeNull()
  })
  it('keeps -- literal inside inline code', () => {
    const doc = 'run `npm install --'
    expect(dashArrow(doc, doc.length, doc.length, 's')).toBeNull()
  })
  it('still converts in plain prose', () => {
    expect(dashArrow('word--', 6, 6, 'x')).not.toBeNull()
  })
})

describe("closeConstructOnEnter — contractions don't poison quote parity", () => {
  it('does not teleport the caret past a prose apostrophe', () => {
    const doc = "it's fine, don't"
    expect(closeConstructOnEnter(doc, 14, 14)).toBeNull() // caret before don|'t
  })
  it('still closes a real open quote', () => {
    const doc = "'hello'"
    expect(closeConstructOnEnter(doc, 6, 6)).not.toBeNull() // caret before the closer
  })
})

describe('continueListOnEnter — nested runs + empty-item continuation', () => {
  it('renumbers past a nested sublist instead of duplicating numbers', () => {
    const doc = '1. a\n\t1. child\n2. b'
    const edit = continueListOnEnter(doc, 4, 4)
    expect(edit).not.toBeNull()
    const next = doc.slice(0, edit!.from) + edit!.insert + doc.slice(edit!.to)
    expect(next).toBe('1. a\n2. \n\t1. child\n3. b')
  })
  it('continues on an empty item instead of exiting (no auto-exit)', () => {
    const edit = continueListOnEnter('- ', 2, 2)
    expect(edit).toEqual({ from: 2, to: 2, insert: '\n- ', selection: 5 })
  })
  it('continues an empty item inside a quote, keeping the `> `', () => {
    const doc = '> - '
    const edit = continueListOnEnter(doc, 4, 4)
    expect(edit).toEqual({ from: 4, to: 4, insert: '\n> - ', selection: 9 })
  })
})

describe('continueBlockquoteOnEnter — empty quote line exits', () => {
  it('strips an empty `> ` line instead of continuing forever', () => {
    const edit = continueBlockquoteOnEnter('> ', 2, 2)
    expect(edit).toEqual({ from: 0, to: 2, insert: '', selection: 0 })
  })
  it('keeps continuing inside a callout (its exit is caret placement)', () => {
    const doc = '> [!callout] head\n> '
    const edit = continueBlockquoteOnEnter(doc, 20, 20)
    expect(edit?.insert).toBe('\n> ')
  })
})

describe('outdentListOnShiftTab', () => {
  it('removes one indent level', () => {
    expect(outdentListOnShiftTab('\t- item', 4, 4)).toEqual({
      from: 0,
      to: 1,
      insert: '',
      selection: 3,
    })
  })
  it('no-ops at top level', () => {
    expect(outdentListOnShiftTab('- item', 3, 3)).toBeNull()
  })
})

describe('format transforms — prefix-aware', () => {
  it('setHeading on a quoted list line stays inside the quote', () => {
    const doc = '> - item'
    const { changes } = setHeading(doc, 5, 2)
    expect(changes).toEqual([{ from: 2, to: 8, insert: '## item' }])
  })
  it('setHeading on a callout head edits after the tag — never exposes it', () => {
    const doc = '> [!callout] Title'
    const { changes } = setHeading(doc, 15, 1)
    expect(changes[0].from).toBe(13) // after `> [!callout] `
    expect(changes[0].insert).toBe('# Title')
  })
  it('setList on a quoted line lands the marker inside the quote', () => {
    const doc = '> item'
    const { changes } = setList(doc, 4, 'bullet')
    expect(changes).toEqual([{ from: 2, to: 6, insert: '- item' }])
  })
})

describe('subBlockAt — continuation lines ride with their item', () => {
  it("includes a wrapped item's indented body", () => {
    const doc = '- item one\n  continued text\n- item two'
    expect(subBlockAt(doc, 2)).toEqual({ from: 0, to: 27, level: 0 })
  })
})

describe('renumberOrderedRun — nested lines are skipped, not terminators', () => {
  it('renumbers a run past its sublists', () => {
    const doc = '1. a\n\t1. x\n2. b\n2. c'
    const changes = renumberOrderedRun(doc, 0)
    // 2. b keeps its number; the duplicate 2. c becomes 3.
    expect(changes).toEqual([{ from: 16, to: 17, insert: '3' }])
  })
})

describe('calloutDeleteVerdict — repair, not cancel', () => {
  const doc = '> [!callout] head\n> body' // body at 18, prefix [18,20)
  it('allows a whole-line removal (line + newline)', () => {
    expect(calloutDeleteVerdict(doc, 18, 25).kind).toBe('ok')
  })
  it('clamps an in-line delete-to-line-start to the prefix end', () => {
    expect(calloutDeleteVerdict(doc, 18, 22)).toEqual({ kind: 'clamp', from: 20 })
  })
  it('extends a forward join to consume the body prefix', () => {
    expect(calloutDeleteVerdict(doc, 17, 18)).toEqual({ kind: 'extend', to: 20 })
  })
  it('still cancels pure prefix erosion (a delete confined inside the prefix)', () => {
    expect(calloutDeleteVerdict(doc, 18, 19).kind).toBe('cancel')
  })
  it('neutralizes a whole-prefix in-place delete to a zero-width clamp', () => {
    expect(calloutDeleteVerdict(doc, 19, 20)).toEqual({ kind: 'clamp', from: 20 })
  })
})

describe('renderer fence engine agrees with isInsideCode on ~~~ (no cross-layer split)', () => {
  it('fencedCodeRanges recognizes a ~~~ block', () => {
    const doc = '~~~\n[[LivePage]]\n~~~'
    const ranges = fencedCodeRanges(doc)
    expect(ranges.length).toBe(1)
    // the connection sits inside the code range → renderer won't make it live
    expect(ranges[0][0]).toBeLessThanOrEqual(4)
    expect(ranges[0][1]).toBeGreaterThanOrEqual(15)
  })
  it('pairs by marker char — a ~~~ line inside ``` is content, not a close', () => {
    const doc = '```\n~~~\ncode\n```\nprose'
    const ranges = fencedCodeRanges(doc)
    expect(ranges.length).toBe(1) // one block, not split at the ~~~ line
    expect(isInsideCode(9, doc)).toBe(true) // input layer agrees
  })
})

describe('dashArrow — link-target guard (relative paths, anchors)', () => {
  it('keeps -- literal inside a relative link target', () => {
    const doc = '[text](../foo--'
    expect(dashArrow(doc, doc.length, doc.length, 'x')).toBeNull()
  })
  it('still converts once the link target is closed', () => {
    const doc = '[text](../foo) then a--'
    expect(dashArrow(doc, doc.length, doc.length, 'x')).not.toBeNull()
  })
})

describe('headingSections — fence-blind no more', () => {
  it('ignores # lines inside code fences', () => {
    const doc = '## Real\nprose\n```bash\n# comment\necho hi\n```\ntail'
    const sections = headingSections(doc)
    expect(sections).toHaveLength(1)
    expect(sections[0].key).toBe('Real')
    expect(sections[0].to).toBe(doc.length) // section runs past the fence, not cut at the comment
  })
})
