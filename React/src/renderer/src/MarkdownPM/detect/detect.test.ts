import { describe, it, expect } from 'vitest'
import {
  isThematicBreakLine,
  isHeadingLine,
  isBlockquoteLine,
  isDashBulletLine,
  hasCheckbox,
  isInlineMathContent,
  listRegex,
  imageEmbedRegex,
  inlineCodeRegex,
  markdownLinkRegex
} from './index'
import { pageLinkPattern } from '@shared/connections'

describe('thematic break (HR)', () => {
  it('treats ---, ***, ___ as HR; rejects too-short / list lines', () => {
    expect(isThematicBreakLine('---')).toBe(true)
    expect(isThematicBreakLine('***')).toBe(true)
    expect(isThematicBreakLine('___')).toBe(true)
    expect(isThematicBreakLine('--')).toBe(false)
    expect(isThematicBreakLine('- a')).toBe(false)
  })
  it('--- is always HR (no setext interpretation)', () => {
    // Detection is per-line, so a lone "---" is HR regardless of any preceding text.
    expect(isThematicBreakLine('---')).toBe(true)
  })
})

describe('heading', () => {
  it('needs 1-6 # then a space or EOL, ≤3 leading spaces', () => {
    expect(isHeadingLine('# H')).toBe(true)
    expect(isHeadingLine('###### H')).toBe(true)
    expect(isHeadingLine('   # H')).toBe(true) // 3 leading spaces ok
    expect(isHeadingLine('#H')).toBe(false) // no space → not a heading
    expect(isHeadingLine('####### H')).toBe(false) // 7 # → not a heading
    expect(isHeadingLine('    # H')).toBe(false) // 4 spaces → indented code
  })
})

describe('lists + dash bullets', () => {
  it('listRegex matches bullets, ordered, and the -[] shorthand as a list LINE', () => {
    expect(listRegex().test('- a')).toBe(true)
    expect(listRegex().test('1. a')).toBe(true)
    expect(listRegex().test('-[] a')).toBe(true) // bare -[] still reads as a list line
  })
  it('isDashBulletLine: only "-" marker, and NOT task lines', () => {
    expect(isDashBulletLine('- a')).toBe(true)
    expect(isDashBulletLine('* a')).toBe(false) // only - substitutes a glyph
    expect(isDashBulletLine('+ a')).toBe(false)
    expect(isDashBulletLine('- [ ] a')).toBe(false) // task line excluded
    expect(isDashBulletLine('-[] a')).toBe(false) // any bracket excluded
  })
})

describe('task checkbox', () => {
  it('requires a non-empty inner char; empty [] is NOT a checkbox', () => {
    expect(hasCheckbox('- [ ] a')).toBe(true)
    expect(hasCheckbox('- [x] a')).toBe(true)
    expect(hasCheckbox('- [X] a')).toBe(true)
    expect(hasCheckbox('-[] a')).toBe(false) // empty inner
    expect(hasCheckbox('- a')).toBe(false)
  })
})

describe('blockquote', () => {
  it('needs > then a space/tab (bare > does not activate)', () => {
    expect(isBlockquoteLine('> a')).toBe(true)
    expect(isBlockquoteLine('>a')).toBe(false)
    expect(isBlockquoteLine('>')).toBe(false)
  })
})

describe('inline matchers (verbatim regexes)', () => {
  it('image embed ![[name]]', () => {
    const m = imageEmbedRegex().exec('see ![[pic]] here')
    expect(m?.[1]).toBe('pic')
  })
  it('inline code `code`', () => {
    const m = inlineCodeRegex().exec('a `x` b')
    expect(m?.[1]).toBe('x')
  })
  it('markdown link [t](u)', () => {
    const m = markdownLinkRegex().exec('[t](http://u)')
    expect(m?.[1]).toBe('t')
    expect(m?.[2]).toBe('http://u')
  })
  it('wikilink detection reuses @shared/connections (title-only, excludes ![[ ]])', () => {
    expect([...'[[Page]]'.matchAll(pageLinkPattern())].map((m) => m[1])).toEqual(['Page'])
    expect([...'![[img]]'.matchAll(pageLinkPattern())]).toHaveLength(0)
  })
})

describe('inline math heuristic', () => {
  it('accepts mathy / short letter content; rejects currency + prose', () => {
    expect(isInlineMathContent('x+1')).toBe(true)
    expect(isInlineMathContent('x')).toBe(true)
    expect(isInlineMathContent('5')).toBe(false) // currency-like
    expect(isInlineMathContent('word')).toBe(false) // prose, no mathy chars
  })
})
