import { describe, it, expect } from 'vitest'
import { tokenize, activeTokenIndices, type Token } from './index'

const byKind = (tokens: Token[], kind: string): Token[] => tokens.filter((t) => t.kind === kind)
const slice = (text: string, r: [number, number]): string => text.slice(r[0], r[1])

describe('emphasis tokens (marker geometry)', () => {
  it('*a* → italic with correct markers + content', () => {
    const t = '*a*'
    const em = byKind(tokenize(t), 'italic')[0]
    expect(slice(t, em.contentRange)).toBe('a')
    expect(em.markerRanges.map((m) => slice(t, m))).toEqual(['*', '*'])
  })

  it('**a** → bold with ** markers', () => {
    const t = '**a**'
    const b = byKind(tokenize(t), 'bold')[0]
    expect(slice(t, b.contentRange)).toBe('a')
    expect(b.markerRanges.map((m) => slice(t, m))).toEqual(['**', '**'])
  })

  it('***a*** → content "a" is covered by both bold and italic', () => {
    const t = '***a***'
    const tokens = tokenize(t)
    expect(slice(t, byKind(tokens, 'bold')[0].contentRange)).toBe('a')
    expect(slice(t, byKind(tokens, 'italic')[0].contentRange)).toContain('a')
  })

  it('**a *b* c** → one bold span + nested italic on "b"', () => {
    const t = '**a *b* c**'
    const tokens = tokenize(t)
    expect(byKind(tokens, 'bold')).toHaveLength(1)
    expect(slice(t, byKind(tokens, 'italic')[0].contentRange)).toBe('b')
  })

  it('no emphasis inside inline code', () => {
    const tokens = tokenize('`*a*`')
    expect(byKind(tokens, 'italic')).toHaveLength(0)
    expect(byKind(tokens, 'inlineCode')).toHaveLength(1)
  })
})

describe('inline regex tokens + overlap rules', () => {
  it('wikilink [[Page]] (title-only content)', () => {
    const t = '[[Page]]'
    const w = byKind(tokenize(t), 'wikiLink')[0]
    expect(slice(t, w.contentRange)).toBe('Page')
    expect(w.markerRanges.map((m) => slice(t, m))).toEqual(['[[', ']]'])
  })

  it('image ![[pic]] wins over wikilink (no wikiLink emitted)', () => {
    const tokens = tokenize('![[pic]]')
    expect(byKind(tokens, 'imageEmbed')).toHaveLength(1)
    expect(byKind(tokens, 'wikiLink')).toHaveLength(0)
  })

  it('inline latex $x+1$ tokenizes; prose $word here$ does not', () => {
    expect(byKind(tokenize('$x+1$'), 'inlineLatex')).toHaveLength(1)
    expect(byKind(tokenize('$word here$'), 'inlineLatex')).toHaveLength(0)
  })

  it('markdown link [t](u)', () => {
    const t = '[t](http://u)'
    const l = byKind(tokenize(t), 'link')[0]
    expect(slice(t, l.contentRange)).toBe('t')
  })
})

describe('activeTokenIndices', () => {
  it('caret inside a token marks it active; before it does not', () => {
    const t = 'a *b* c' // italic at [2,5]
    const tokens = tokenize(t)
    const idx = tokens.findIndex((tk) => tk.kind === 'italic')
    expect(activeTokenIndices(tokens, 3, 3).has(idx)).toBe(true)
    expect(activeTokenIndices(tokens, 0, 0).has(idx)).toBe(false)
  })

  it('caret at a wikilink end is NOT active (closing ]] passed)', () => {
    const tokens = tokenize('[[P]]') // wikilink [0,5]
    const idx = tokens.findIndex((tk) => tk.kind === 'wikiLink')
    expect(activeTokenIndices(tokens, 5, 5).has(idx)).toBe(false)
  })
})
