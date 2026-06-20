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

  it('strikethrough → md-strike on content', () => {
    const t = '~~gone~~'
    const tokens = tokenize(t)
    expect(decorationsFor(t, tokens, new Set(), 99).some((d) => d.kind === 'class' && d.className === 'md-strike')).toBe(
      true
    )
  })

  it('dash bullet → a bullet widget over the dash', () => {
    const t = '- item'
    const intents = decorationsFor(t, tokenize(t), new Set(), 99)
    expect(intents.some((d) => d.kind === 'widget' && d.spec.type === 'bullet')).toBe(true)
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
})
