import { describe, it, expect } from 'vitest'
import { tokenize, activeTokenIndices } from '../tokens'
import { decorationsFor } from './intent'

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

  it('connection wikilink content gets md-connection', () => {
    const t = '[[Page]]'
    const tokens = tokenize(t)
    const intents = decorationsFor(t, tokens, new Set(), 99)
    expect(intents.some((d) => d.kind === 'class' && d.className === 'md-connection')).toBe(true)
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
      intents.some((d) => d.kind === 'class' && d.className === 'md-ol-marker md-syntax' && d.from === 0 && d.to === 2)
    ).toBe(true)
    expect(intents.some((d) => d.kind === 'line' && d.className === 'md-li md-li-ordered')).toBe(true)
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
