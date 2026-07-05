import { describe, it, expect } from 'vitest'
import { tokenize, activeTokenIndices } from '../tokens'
import { decorationsFor, type DecoIntent } from './intent'

describe('decoration intents', () => {
  it('inactive bold → md-bold class on content + hidden markers', () => {
    const t = '**a** xxxxx'
    const tokens = tokenize(t)
    const active = activeTokenIndices(tokens, t.length, t.length) // caret far away
    const intents = decorationsFor(t, tokens, active, t.length)
    expect(intents.some((d) => d.kind === 'class' && d.className === 'md-bold')).toBe(true)
    expect(intents.filter((d) => d.kind === 'hide')).toHaveLength(2) // the two ** markers
  })

  it('active bold → markers shown (no hide intents)', () => {
    const t = '**a**'
    const tokens = tokenize(t)
    const active = activeTokenIndices(tokens, 3, 3) // caret inside
    const intents = decorationsFor(t, tokens, active, 3)
    expect(intents.filter((d) => d.kind === 'hide')).toHaveLength(0)
  })

  it('HR → hr widget when the caret is off the line, nothing when on it', () => {
    const t = 'a\n---\nb'
    const tokens = tokenize(t)
    const off = decorationsFor(t, tokens, new Set(), 0) // caret on line 1
    expect(off.some((d) => d.kind === 'widget' && d.spec.type === 'hr')).toBe(true)
    const on = decorationsFor(t, tokens, new Set(), 3) // caret on the --- line (offsets 2–5)
    expect(on.some((d) => d.kind === 'widget' && d.spec.type === 'hr')).toBe(false)
  })

  it('leaves wikilinks untouched — they are rendered in decorations.ts by resolution status', () => {
    const t = '[[Page]]'
    const intents = decorationsFor(t, tokenize(t), new Set(), 99)
    expect(intents).toHaveLength(0) // no content class, no bracket hide — status-dependent
  })

  it('heading sizes the whole line (markers grow too) + mutes the # markers', () => {
    const t = '## Title'
    const intents = decorationsFor(t, tokenize(t), new Set(), 99) // caret off the line
    // whole-line size class so the ## grows with the level
    expect(intents.some((d) => d.kind === 'class' && d.className === 'md-h2' && d.from === 0 && d.to === t.length)).toBe(
      true
    )
    expect(intents.some((d) => d.kind === 'class' && d.className === 'md-hmarker')).toBe(true)
  })

  it('strikethrough → md-strike on content', () => {
    const t = '~~gone~~'
    const tokens = tokenize(t)
    expect(decorationsFor(t, tokens, new Set(), 99).some((d) => d.kind === 'class' && d.className === 'md-strike')).toBe(
      true
    )
  })

  it('dash bullet, caret off the line → • widget replaces just the dash (in-flow)', () => {
    const t = '- item'
    const intents = decorationsFor(t, tokenize(t), new Set(), 99)
    expect(intents.some((d) => d.kind === 'line' && d.className === 'md-li' && d.level === 0)).toBe(true)
    expect(intents.some((d) => d.kind === 'widget' && d.spec.type === 'bullet' && d.from === 0 && d.to === 1)).toBe(true)
  })

  it('dash bullet, caret in the CONTENT (just in the line) → still • widget, never raw', () => {
    const t = '- item'
    const intents = decorationsFor(t, tokenize(t), new Set(), 4) // caret inside "item"
    expect(intents.some((d) => d.kind === 'widget' && d.spec.type === 'bullet')).toBe(true)
  })

  it('dash bullet, caret ON the marker (the dash) → raw `-`, no widget', () => {
    const t = '- item'
    const intents = decorationsFor(t, tokenize(t), new Set(), 1) // caret right on the dash
    expect(intents.some((d) => d.kind === 'line' && d.className === 'md-li')).toBe(true)
    expect(intents.some((d) => d.kind === 'widget')).toBe(false)
  })

  it('ordered list → number kept as literal source (recolour mark), no widget', () => {
    const t = '3. third'
    const intents = decorationsFor(t, tokenize(t), new Set(), 99)
    expect(
      intents.some((d) => d.kind === 'class' && d.className === 'md-ol-marker md-control md-li-glyph' && d.from === 0 && d.to === 2)
    ).toBe(true)
    expect(intents.some((d) => d.kind === 'line' && d.className === 'md-li md-li-ordered')).toBe(true)
    expect(intents.some((d) => d.kind === 'widget')).toBe(false)
  })

  it.each([
    ['arrow', '→ step'],
    ['plus', '+ step']
  ])('%s list → marker kept as literal source (recolour + drag-handle class), no widget, bullet spacing', (_n, t) => {
    const intents = decorationsFor(t, tokenize(t), new Set(), 99)
    expect(intents.some((d) => d.kind === 'class' && d.className === 'md-control md-li-glyph' && d.from === 0 && d.to === 1)).toBe(true)
    expect(intents.some((d) => d.kind === 'line' && d.className === 'md-li')).toBe(true)
    expect(intents.some((d) => d.kind === 'widget')).toBe(false)
  })

  it('nested bullet → line decoration carries the indent level (2 spaces = 1, tab = 1)', () => {
    const spaces = decorationsFor('  - x', tokenize('  - x'), new Set(), 99)
    expect(spaces.some((d) => d.kind === 'line' && d.level === 1)).toBe(true)
    const tab = decorationsFor('\t\t- x', tokenize('\t\t- x'), new Set(), 99)
    expect(tab.some((d) => d.kind === 'line' && d.level === 2)).toBe(true)
  })

  it('task checkbox → a checkbox widget carrying bracket range + checked state', () => {
    const t = '- [x] done'
    const w = decorationsFor(t, tokenize(t), new Set(), 99).find((d) => d.kind === 'widget')
    expect(w?.kind === 'widget' && w.spec.type === 'checkbox' && w.spec.checked).toBe(true)
    // unchecked
    const t2 = '- [ ] todo'
    const w2 = decorationsFor(t2, tokenize(t2), new Set(), 99).find((d) => d.kind === 'widget')
    expect(w2?.kind === 'widget' && w2.spec.type === 'checkbox' && w2.spec.checked).toBe(false)
  })

  it('task checkbox, caret ON the marker → raw `- [ ] `, no widget (parity with bullets)', () => {
    const t = '- [ ] todo'
    const intents = decorationsFor(t, tokenize(t), new Set(), 2) // caret inside the box
    expect(intents.some((d) => d.kind === 'line' && d.className === 'md-li md-li-task')).toBe(true)
    expect(intents.some((d) => d.kind === 'widget')).toBe(false)
  })

  it('blockquote → md-bq line + permanently hidden marker; a lone line is first AND last', () => {
    const t = '> quote'
    const intents = decorationsFor(t, tokenize(t), new Set(), 0) // caret on the line — still hidden
    const line = intents.find((d) => d.kind === 'line')
    expect(line?.kind === 'line' && line.className).toBe('md-bq md-bq-first md-bq-last')
    expect(intents.some((d) => d.kind === 'hide' && d.from === 0 && d.to === 2)).toBe(true) // "> "
  })

  it('multi-line blockquote → only the outer lines round (first vs last)', () => {
    const t = '> a\n> b'
    const lines = decorationsFor(t, tokenize(t), new Set(), 99).filter(
      (d): d is Extract<typeof d, { kind: 'line' }> => d.kind === 'line'
    )
    expect(lines).toHaveLength(2)
    expect(lines[0].className).toBe('md-bq md-bq-first')
    expect(lines[1].className).toBe('md-bq md-bq-last')
  })

  it('fenced code block → md-cb lines (open/content/close); fences hidden with caret outside', () => {
    const t = 'p\n```js\ncode\n```'
    const intents = decorationsFor(t, tokenize(t), new Set(), 0) // caret on "p", outside the block
    const classes = intents
      .filter((d): d is Extract<typeof d, { kind: 'line' }> => d.kind === 'line')
      .map((d) => d.className)
    expect(classes).toEqual(['md-cb md-cb-first', 'md-cb', 'md-cb md-cb-last'])
    expect(intents.filter((d) => d.kind === 'hide')).toHaveLength(2) // both fence lines' markers
  })

  it('fenced code block → fence markers reveal when the caret is inside the block', () => {
    const t = '```js\ncode\n```'
    const intents = decorationsFor(t, tokenize(t), new Set(), 7) // caret in "code"
    expect(intents.filter((d) => d.kind === 'hide')).toHaveLength(0)
  })
})

describe('callout box chrome + nested constructs', () => {
  const doc = '> [!callout] hi\n> - item\n> ## head\n> ---'
  const intents = decorationsFor(doc, tokenize(doc), new Set(), 0)
  const lineClasses = intents.filter((d): d is Extract<typeof d, { kind: 'line' }> => d.kind === 'line').map((d) => d.className)

  it('every line gets the box line-class (first/last)', () => {
    expect(lineClasses.some((c) => c.includes('md-callout-first'))).toBe(true)
    expect(lineClasses.some((c) => c.includes('md-callout-last'))).toBe(true)
  })
  it('a bullet inside the box still composes md-li with the box', () => {
    expect(lineClasses).toContain('md-li')
  })
  it('the bullet widget absorbs the prefix (starts at line start, not touching a separate hide)', () => {
    const lineStart = doc.indexOf('> - item')
    const w = intents.find((d) => d.kind === 'widget' && d.spec.type === 'bullet')
    expect(w && w.from).toBe(lineStart)
  })
  it('a heading + HR render inside the box', () => {
    expect(intents.some((d) => d.kind === 'class' && d.className === 'md-h2')).toBe(true)
    expect(intents.some((d) => d.kind === 'widget' && d.spec.type === 'hr')).toBe(true)
  })
  it('a top-level code block quoting a ``` line stays ONE block (fences pair by quote-depth, not greedily)', () => {
    const t = '```\n> ```\nstill code\n```'
    const ints = decorationsFor(t, tokenize(t), new Set(), 99) // caret off the block
    // all of lines 1-2 are code CONTENT (no md-cb-last until the final ```), so exactly one open + one close
    const cbLines = ints.filter((d): d is Extract<typeof d, { kind: 'line' }> => d.kind === 'line' && d.className.includes('md-cb'))
    expect(cbLines.filter((d) => d.className.includes('md-cb-first'))).toHaveLength(1)
    expect(cbLines.filter((d) => d.className.includes('md-cb-last'))).toHaveLength(1)
    expect(cbLines).toHaveLength(4) // 4 lines, all one block
  })
  it('an unclosed fence inside a callout does not leak code styling onto the non-quote lines below', () => {
    const t = '> [!callout] head\n> ```\nplain below\nmore plain'
    const ints = decorationsFor(t, tokenize(t), new Set(), 99)
    const cbLines = ints.filter((d): d is Extract<typeof d, { kind: 'line' }> => d.kind === 'line' && d.className.includes('md-cb'))
    // only the `> ``` open line is a code line; the non-quote lines below are NOT code
    expect(cbLines).toHaveLength(1)
  })
  it('a blockquote nested inside a callout renders as an inset quote (md-bq-in), not flat body', () => {
    const t = '> [!callout] head\n> > quoted one\n> > quoted two\n> body'
    const ints = decorationsFor(t, tokenize(t), new Set(), 99)
    const classes = ints.filter((d): d is Extract<typeof d, { kind: 'line' }> => d.kind === 'line').map((d) => d.className)
    expect(classes.some((c) => c.includes('md-bq-in-first'))).toBe(true)
    expect(classes.some((c) => c.includes('md-bq-in-last'))).toBe(true)
    expect(classes.filter((c) => c.includes('md-bq-in')).length).toBe(2) // both quote lines
    // the whole `> > ` is hidden (one callout level + one quote level)
    expect(ints.some((d) => d.kind === 'hide' && d.to - d.from === 4)).toBe(true)
  })
  it('a multi-DEPTH nested-quote run is ONE block — exactly one first + one last, no notch mid-block', () => {
    const t = '> [!callout] head\n> > a\n> >> b\n> > c\n> body'
    const ints = decorationsFor(t, tokenize(t), new Set(), 99)
    const classes = ints.filter((d): d is Extract<typeof d, { kind: 'line' }> => d.kind === 'line').map((d) => d.className)
    expect(classes.filter((c) => c.includes('md-bq-in-first'))).toHaveLength(1)
    expect(classes.filter((c) => c.includes('md-bq-in-last'))).toHaveLength(1)
    expect(classes.filter((c) => c.includes('md-bq-in')).length).toBe(3) // a, b, c all in the run
  })
  it('a fenced code block inside a callout composes the box chrome with the code class', () => {
    const t = '> [!callout] head\n> ```js\n> code\n> ```'
    const ints = decorationsFor(t, tokenize(t), new Set(), 0)
    const classes = ints.filter((d): d is Extract<typeof d, { kind: 'line' }> => d.kind === 'line').map((d) => d.className)
    expect(classes).toContain('md-cb md-cb-first') // the ```js line
    expect(classes.some((c) => c.startsWith('md-callout') && !c.includes('md-cb'))).toBe(true) // box chrome present
    // every fence line is also a callout line (the box wraps the code)
    expect(classes.filter((c) => c.includes('md-callout')).length).toBe(4)
  })
})

describe('outliner rails', () => {
  type Rail = Extract<DecoIntent, { kind: 'rail' }>
  const rails = (t: string): Rail[] =>
    decorationsFor(t, tokenize(t), new Set(), 999).filter((d): d is Rail => d.kind === 'rail')

  it('a top-level item has no ancestor rails', () => {
    expect(rails('- solo')).toHaveLength(0)
  })

  it('nesting emits one rail per ancestor level, with caps only at each run’s ends', () => {
    // levels: A0 B1 C2 D1 E0 — the worked run: level-0 rail spans B→C→D, level-1 rail is C alone.
    const t = '- A\n\t- B\n\t\t- C\n\t- D\n- E'
    const rs = rails(t)
    const has = (level: number, first: boolean, last: boolean): number =>
      rs.filter((r) => r.level === level && r.first === first && r.last === last).length
    expect(rs).toHaveLength(4) // B(1) + C(2) + D(1)
    expect(has(0, true, false)).toBe(1) // B — run start under A
    expect(has(0, false, false)).toBe(1) // C — mid-run
    expect(has(0, false, true)).toBe(1) // D — run end
    expect(has(1, true, true)).toBe(1) // C — single-line level-1 run under B
    expect(rs.some((r) => r.level >= 2)).toBe(false) // level-2 item has ancestors 0 and 1 only
  })

  it('a rail takes its ANCESTOR’s marker type, not the descendant’s (the checkbox-centre fix)', () => {
    // bullet parent, checkbox child → the child’s rail centres on the bullet, not its own box.
    const bulletParent = rails('- parent\n\t- [ ] child')
    expect(bulletParent).toHaveLength(1)
    expect(bulletParent[0].typeClass).toBe('md-outliner-bullet')

    // checkbox parent, bullet child → the rail centres on the parent’s 17px box.
    const taskParent = rails('- [ ] parent\n\t- child')
    expect(taskParent).toHaveLength(1)
    expect(taskParent[0].typeClass).toBe('md-outliner-task')
  })

  it('rails are scoped to bullets + checkboxes — ordered / arrow / + ancestors get none (deferred)', () => {
    expect(rails('1. parent\n\t- child')).toHaveLength(0) // ordered parent
    expect(rails('→ parent\n\t- child')).toHaveLength(0) // arrow parent
    expect(rails('+ parent\n\t- child')).toHaveLength(0) // + parent
  })

  it('a non-list line between siblings breaks the run (caps on both sides of the gap)', () => {
    const t = '- A\n\t- B\nprose\n\t- C'
    const rs = rails(t)
    // B: run ends at the prose gap (next line not a list) → last true. C: run starts after the gap → first true.
    expect(rs.filter((r) => r.level === 0 && r.last).length).toBe(2) // B and C both cap at the break
    expect(rs.filter((r) => r.level === 0 && r.first).length).toBe(2)
  })
})
