import { describe, it, expect } from 'vitest'
import {
  continueListOnEnter,
  smartBackspace,
  canonicalizeCheckbox,
  autoPair,
  autoDelete,
  closeConstructOnEnter,
  closeConstructOnShiftEnter,
  dashArrow,
  indentListOnTab,
  continueBlockquoteOnEnter,
  calloutShorthand,
  shiftEnterEdit,
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
  it('renumbers the following siblings when inserting mid-list (1,2 → 1,2,3)', () => {
    const doc = '1. a\n2. b'
    const e = continueListOnEnter(doc, 4, 4)! // Enter at the end of "1. a"
    expect(apply(doc, e)).toBe('1. a\n2. \n3. b')
    expect(e.selection).toBe(8) // caret at the new item's content
  })
  it('renumbers a longer run (1,2,3 → insert at 1 → 1,2,3,4)', () => {
    const doc = '1. a\n2. b\n3. c'
    const e = continueListOnEnter(doc, 4, 4)!
    expect(apply(doc, e)).toBe('1. a\n2. \n3. b\n4. c')
  })
  it('continues a checkbox as a fresh unchecked box', () => {
    const doc = '- [x] done'
    const e = continueListOnEnter(doc, doc.length, doc.length)!
    expect(apply(doc, e)).toBe('- [x] done\n- [ ] ')
  })
  it('continues even on an empty item — no auto-exit (Enter always breeds a bullet)', () => {
    const doc = '- '
    const e = continueListOnEnter(doc, doc.length, doc.length)!
    expect(apply(doc, e)).toBe('- \n- ')
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
  it('{ is removed from the auto-pair system — no pairing, no paired-delete', () => {
    expect(autoPair('', 0, 0, '{')).toBeNull()
    expect(autoDelete('{}', 1, 1)).toBeNull()
  })
  it('[[ collapses the existing closer instead of stacking a stray ]', () => {
    // doc is "[]" with caret after the first "[" (the first [ already auto-paired)
    const e = autoPair('[]', 1, 1, '[')!
    expect(apply('[]', e)).toBe('[[]]') // not "[[]]]"
    expect(e.selection).toBe(2)
  })
  it('(( collapses the existing closer', () => {
    const e = autoPair('()', 1, 1, '(')!
    expect(apply('()', e)).toBe('(())')
    expect(e.selection).toBe(2)
  })
  it('quotes pair at line start / after whitespace', () => {
    expect(autoPair('', 0, 0, '"')).not.toBeNull()
    expect(autoPair('say ', 4, 4, "'")).not.toBeNull()
  })
  it('a quote right after a word char stays literal (apostrophes / units)', () => {
    expect(autoPair('don', 3, 3, "'")).toBeNull() // don|'t
    expect(autoPair('5', 1, 1, '"')).toBeNull() // 5"
  })
  it('typing a quote over its own closer steps past it (no stray)', () => {
    const e = autoPair("''", 1, 1, "'")! // '|' , type ' to close
    expect(e.insert).toBe('')
    expect(e.selection).toBe(2)
  })
  it('backspace inside an empty quote pair deletes both halves', () => {
    expect(apply('""', autoDelete('""', 1, 1)!)).toBe('')
    expect(apply("''", autoDelete("''", 1, 1)!)).toBe('')
  })
  it('single emphasis * / _ / ` pair when not after a word char', () => {
    expect(apply('', autoPair('', 0, 0, '*')!)).toBe('**') // *|*
    expect(autoPair('say ', 4, 4, '_')).not.toBeNull()
    expect(autoPair('', 0, 0, '`')).not.toBeNull()
  })
  it('emphasis stays literal after a word char (2 * 3, snake_case)', () => {
    expect(autoPair('2 ', 2, 2, '*')).not.toBeNull() // after space → pairs
    expect(autoPair('x', 1, 1, '*')).toBeNull() // x* → literal
    expect(autoPair('foo', 3, 3, '_')).toBeNull() // foo_bar → literal
  })
  it('the second * still promotes the pair to bold (**|**)', () => {
    const e = autoPair('**', 1, 1, '*')! // caret in *|* , type 2nd *
    expect(apply('**', e)).toBe('****')
    expect(e.selection).toBe(2)
  })
  it('backspace inside an empty emphasis pair deletes both halves', () => {
    expect(apply('**', autoDelete('**', 1, 1)!)).toBe('')
    expect(apply('``', autoDelete('``', 1, 1)!)).toBe('')
  })
})

describe('close construct on Enter', () => {
  it('jumps past a single empty closer', () => {
    const e = closeConstructOnEnter('[]', 1, 1)!
    expect(e.selection).toBe(2)
    expect(e.insert).toBe('')
  })
  it('double-jumps an empty [[ | ]]', () => {
    expect(closeConstructOnEnter('[[]]', 2, 2)!.selection).toBe(4)
  })
  it('closes a connection with content: [[word|]] → past ]]', () => {
    expect(closeConstructOnEnter('[[word]]', 6, 6)!.selection).toBe(8)
  })
  it('closes a quote / emphasis with content (caret before the closer)', () => {
    expect(closeConstructOnEnter('"hi"', 3, 3)!.selection).toBe(4) // "hi|" → past "
    expect(closeConstructOnEnter('*hi*', 3, 3)!.selection).toBe(4) // *hi|* → past *
    expect(closeConstructOnEnter('**hi**', 4, 4)!.selection).toBe(6) // **hi|** → past **
  })
  it('does nothing when the char ahead is not a matching closer', () => {
    expect(closeConstructOnEnter('hello)', 5, 5)).toBeNull() // a stray ) with no ( before
    expect(closeConstructOnEnter('plain', 5, 5)).toBeNull()
  })
  it('does NOT close a new pair following an already-closed one (parity, not presence)', () => {
    expect(closeConstructOnEnter('**a****b**', 5, 5)).toBeNull() // caret between two complete **…** pairs
    expect(closeConstructOnEnter('"a""b"', 3, 3)).toBeNull() // caret between two complete "…" pairs
  })
})

describe('Shift+Enter closes the construct first, then breaks the line', () => {
  it('closes then newlines: "hi|" → "hi"\\n|', () => {
    const e = closeConstructOnShiftEnter('"hi"', 3, 3)!
    expect(apply('"hi"', e)).toBe('"hi"\n') // closer preserved, newline after it
  })
  it('connection: [[word|]] → [[word]]\\n|', () => {
    expect(apply('[[word]]', closeConstructOnShiftEnter('[[word]]', 6, 6)!)).toBe('[[word]]\n')
  })
  it('is null outside any construct (falls back to a plain break)', () => {
    expect(closeConstructOnShiftEnter('plain', 5, 5)).toBeNull()
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
  it('<-> → ↔ (two-step chain)', () => {
    const afterBackArrow = apply('<', dashArrow('<', 1, 1, '-')!)
    expect(afterBackArrow).toBe('←')
    expect(apply(afterBackArrow, dashArrow(afterBackArrow, 1, 1, '>')!)).toBe('↔')
  })
  it('spaced " - " second space → en-dash', () => {
    const doc = 'a -'
    expect(apply(doc, dashArrow(doc, 3, 3, ' ')!)).toBe('a – ')
  })
})

describe('tab indent (list nesting)', () => {
  it('nests a bullet by inserting a tab at line start, caret follows', () => {
    const doc = '- item'
    const e = indentListOnTab(doc, doc.length, doc.length)!
    expect(apply(doc, e)).toBe('\t- item')
    expect(e.selection).toBe(doc.length + 1)
  })
  it('counts 2 spaces as one level (4 spaces = level 2, still under the cap)', () => {
    const doc = '    - two'
    expect(apply(doc, indentListOnTab(doc, doc.length, doc.length)!)).toBe('\t    - two')
  })
  it('caps at the max nesting level (3 tabs → no further indent)', () => {
    expect(indentListOnTab('\t\t\t- deep', 9, 9)).toBeNull()
  })
  it('ignores non-list lines and selections', () => {
    expect(indentListOnTab('plain text', 5, 5)).toBeNull()
    expect(indentListOnTab('- item', 2, 4)).toBeNull()
  })
})

describe('blockquote continuation (Enter)', () => {
  it('continues a quote with the same prefix', () => {
    const doc = '> quote'
    expect(apply(doc, continueBlockquoteOnEnter(doc, doc.length, doc.length)!)).toBe('> quote\n> ')
  })
  it('preserves nesting depth', () => {
    const doc = '>> deep'
    expect(apply(doc, continueBlockquoteOnEnter(doc, doc.length, doc.length)!)).toBe('>> deep\n>> ')
  })
  it('falls through when the caret is in the marker, or on a non-quote line', () => {
    expect(continueBlockquoteOnEnter('> q', 1, 1)).toBeNull()
    expect(continueBlockquoteOnEnter('plain', 5, 5)).toBeNull()
  })
})

describe('callout shorthand (||)', () => {
  // The second `|` is intercepted; the first already sits at c-1 in the doc.
  it('expands `||` at line start to the callout head + a trailing exit line at doc end', () => {
    const doc = '|' // first `|` typed; second `|` about to land at pos 1
    expect(apply(doc, calloutShorthand(doc, 1, 1, '|')!)).toBe('> [!callout] \n')
  })
  it('reuses an existing following line as the exit target (no extra newline)', () => {
    const doc = '|\nafter'
    expect(apply(doc, calloutShorthand(doc, 1, 1, '|')!)).toBe('> [!callout] \nafter')
  })
  it('only fires on a bare `|` alone on the line (never mid-line / inside a table)', () => {
    expect(calloutShorthand('a |', 3, 3, '|')).toBeNull()
    expect(calloutShorthand('| x ', 4, 4, '|')).toBeNull()
  })
  it('preserves content already on the line (||ab → callout with "ab" body, no trailing line)', () => {
    const doc = '|ab' // first `|` typed at line start, second about to land at pos 1
    expect(apply(doc, calloutShorthand(doc, 1, 1, '|')!)).toBe('> [!callout] ab')
  })
  it('separates from a callout directly above with a blank line (no touching boxes / merged run)', () => {
    const doc = '> [!callout] first\n|' // `|` typed on the line below an existing callout
    expect(apply(doc, calloutShorthand(doc, 20, 20, '|')!)).toBe('> [!callout] first\n\n> [!callout] \n')
  })
})

describe('dash auto-format is prefix-aware', () => {
  it('does NOT convert a `- ` bullet into an en-dash inside a quote/callout', () => {
    const doc = '> -' // about to type the space after the bullet dash
    expect(dashArrow(doc, 3, 3, ' ')).toBeNull()
  })
  it('still converts a real ` - ` range inside a callout (prose before the dash)', () => {
    const doc = '> [!callout] Mon -'
    expect(apply(doc, dashArrow(doc, doc.length, doc.length, ' ')!)).toBe('> [!callout] Mon – ')
  })
})

describe('shift+enter', () => {
  it('exits with a plain newline outside a callout', () => {
    expect(shiftEnterEdit('hello', 5, 5).insert).toBe('\n')
  })
  it('stays in the box (continues the `>` prefix) inside a callout', () => {
    const doc = '> [!callout] hi'
    expect(shiftEnterEdit(doc, doc.length, doc.length).insert).toBe('\n> ')
  })
  it('with a selection inside a callout still keeps the box prefix (no run-splitting plain newline)', () => {
    const doc = '> [!callout] head\n> abcXYZdef'
    const a = doc.indexOf('XYZ')
    const e = a + 3
    expect(apply(doc, shiftEnterEdit(doc, a, e))).toBe('> [!callout] head\n> abc\n> def')
  })
  it('a selection STRADDLING the box edge falls back to plain newline (no outside text pulled in)', () => {
    const doc = '> [!callout] body here\nplain below line'
    const a = doc.indexOf('body here')
    const e = doc.indexOf('below') // head is in the plain line, outside the callout
    expect(apply(doc, shiftEnterEdit(doc, a, e))).toBe('> [!callout] \nbelow line') // no `>` on "below line"
  })
})

describe('nested list behaviour inside a callout', () => {
  const callout = (body: string): string => `> [!callout] head\n${body}`
  it('Enter continues a bullet inside the box (keeps the `>` prefix)', () => {
    const doc = callout('> - item')
    expect(apply(doc, continueListOnEnter(doc, doc.length, doc.length)!)).toBe(callout('> - item\n> - '))
  })
  it('Enter continues + renumbers an ordered list inside the box', () => {
    const doc = callout('> 1. a')
    expect(apply(doc, continueListOnEnter(doc, doc.length, doc.length)!)).toBe(callout('> 1. a\n> 2. '))
  })
  it('Tab indents the inner list after the prefix, not before the `>`', () => {
    const doc = callout('> - item')
    expect(apply(doc, indentListOnTab(doc, doc.length, doc.length)!)).toBe(callout('> \t- item'))
  })
  it('backspace deletes the inner marker (de-lists) but keeps the box', () => {
    const doc = callout('> - x')
    const contentStart = doc.length - 1 // before "x"
    expect(apply(doc, smartBackspace(doc, contentStart, contentStart)!)).toBe(callout('> x'))
  })
  it('backspace at a plain body line-start joins up rather than stripping the `>`', () => {
    const doc = '> [!callout] head\n> body'
    const contentStart = doc.indexOf('body')
    expect(apply(doc, smartBackspace(doc, contentStart, contentStart)!)).toBe('> [!callout] headbody')
  })
  it('backspace at the head content-start removes the whole callout marker', () => {
    const doc = '> [!callout] head'
    const cs = '> [!callout] '.length
    expect(apply(doc, smartBackspace(doc, cs, cs)!)).toBe('head')
  })
  it('backspace from INSIDE the hidden tag also removes the whole callout (no char-by-char corruption)', () => {
    const doc = '> [!callout] head'
    expect(apply(doc, smartBackspace(doc, 5, 5)!)).toBe('head') // caret mid-tag (after `> [!`)
  })
  it('-[]+space canonicalizes to GFM behind the prefix', () => {
    const doc = '> [!callout] head\n> -[]'
    const r = canonicalizeCheckbox(doc, doc.length, doc.length, ' ')!
    expect(apply(doc, r)).toBe('> [!callout] head\n> - [ ] ')
  })
})
