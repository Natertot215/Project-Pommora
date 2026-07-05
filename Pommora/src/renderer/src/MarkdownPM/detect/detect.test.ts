import { describe, it, expect } from 'vitest'
import {
  isThematicBreakLine,
  isHeadingLine,
  isBlockquoteLine,
  hasCheckbox,
  isInlineMathContent,
  parseListMarker,
  indentLevel,
  imageEmbedRegex,
  inlineCodeRegex,
  markdownLinkRegex,
  calloutLines,
  lineInCallout,
  calloutHeadPrefixLen,
  parseListMarkerPrefixed
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

describe('parseListMarker (single marker source)', () => {
  it('bullet: ranges + level (2 spaces = 1 level)', () => {
    const m = parseListMarker('  - x')!
    expect(m.kind).toBe('bullet')
    expect(m.bullet).toBe('-')
    expect([m.markerStart, m.markerEnd, m.contentStart]).toEqual([2, 3, 4])
    expect(m.level).toBe(1)
    expect(m.box).toBeUndefined()
  })
  it('ordered: digits + marker spans through the dot', () => {
    const m = parseListMarker('12. y')!
    expect(m.kind).toBe('ordered')
    expect(m.digits).toBe('12')
    expect([m.markerStart, m.markerEnd, m.contentStart]).toEqual([0, 3, 4])
  })
  it('checkbox: bracket span + checked, markerEnd at the bracket end', () => {
    const m = parseListMarker('- [x] done')!
    expect(m.kind).toBe('checkbox')
    expect(m.checked).toBe(true)
    expect([m.box!.start, m.box!.end]).toEqual([2, 5])
    expect(m.markerEnd).toBe(5)
    expect(m.contentStart).toBe(6)
  })
  it('empty [] is a bullet (box present, not a checkbox); ordered "1. [ ]" stays ordered', () => {
    expect(parseListMarker('-[] a')!.kind).toBe('bullet')
    expect(parseListMarker('1. [ ] a')!.kind).toBe('ordered')
  })
  it('arrow: `→ ` is a list marker (the glyph IS the marker), nesting via indent', () => {
    const m = parseListMarker('→ go')!
    expect(m.kind).toBe('arrow')
    expect(m.bullet).toBe('→')
    expect([m.markerStart, m.markerEnd, m.contentStart]).toEqual([0, 1, 2])
    expect(parseListMarker('\t→ nested')!.level).toBe(1)
  })
  it('returns null for non-list lines and markers with no trailing space', () => {
    expect(parseListMarker('plain')).toBeNull()
    expect(parseListMarker('-[x]done')).toBeNull()
    expect(parseListMarker('→go')).toBeNull() // arrow needs a trailing space, like every other marker
  })
  it('indentLevel: tabs + ⌊spaces/2⌋, capped at the max', () => {
    expect(indentLevel('')).toBe(0)
    expect(indentLevel('    ')).toBe(2)
    expect(indentLevel('\t\t\t\t')).toBe(3) // capped
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

  it('nested >> activates', () => {
    expect(isBlockquoteLine('>> a')).toBe(true)
    expect(isBlockquoteLine('>>a')).toBe(false)
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

describe('callout detection', () => {
  it('marks every line of a `[!type]`-headed quote run as a callout (first/last + prefix to hide)', () => {
    const info = calloutLines(['> [!callout] hi', '> more', 'plain'])
    expect(info[0]).toEqual({ first: true, last: false, prefixEnd: '> [!callout] '.length })
    expect(info[1]).toEqual({ first: false, last: true, prefixEnd: '> '.length })
    expect(info[2]).toBeUndefined()
  })
  it('leaves a plain quote (no tag) untouched — callouts coexist with quotes', () => {
    expect(calloutLines(['> just a quote', '> still'])).toEqual([undefined, undefined])
  })
  it('per-head: two adjacent heads are TWO separate callouts, never one box with a raw tag', () => {
    const info = calloutLines(['> [!callout] a', '> [!callout] b'])
    expect(info[0]).toEqual({ first: true, last: true, prefixEnd: '> [!callout] '.length })
    expect(info[1]).toEqual({ first: true, last: true, prefixEnd: '> [!callout] '.length })
  })
  it('per-head: a tag on a non-first quote line starts a callout there (quote above stays a quote)', () => {
    const info = calloutLines(['> a normal quote', '> [!callout] now a callout', '> its body'])
    expect(info[0]).toBeUndefined()
    expect(info[1]?.first).toBe(true)
    expect(info[2]).toEqual({ first: false, last: true, prefixEnd: '> '.length })
  })
  it('lineInCallout reports membership by caret offset', () => {
    const doc = 'top\n> [!callout] hi\n> more\nplain'
    expect(lineInCallout(doc, 0)).toBe(false) // "top"
    expect(lineInCallout(doc, doc.indexOf('hi'))).toBe(true)
    expect(lineInCallout(doc, doc.indexOf('more'))).toBe(true)
    expect(lineInCallout(doc, doc.indexOf('plain'))).toBe(false)
  })
  it('calloutHeadPrefixLen measures the full `> [!type] ` head, null on a body/quote line', () => {
    expect(calloutHeadPrefixLen('> [!callout] hi')).toBe('> [!callout] '.length)
    expect(calloutHeadPrefixLen('> body')).toBeNull()
    expect(calloutHeadPrefixLen('plain')).toBeNull()
  })
})

describe('parseListMarkerPrefixed (lists behind a quote/callout prefix)', () => {
  it('finds a bullet behind `> ` with full-line offsets', () => {
    const lm = parseListMarkerPrefixed('> - item')!
    expect(lm.kind).toBe('bullet')
    expect(lm.markerStart).toBe(2) // the `-` position, prefix included
    expect(lm.contentStart).toBe(4)
  })
  it('finds a checkbox behind `> ` with shifted box offsets', () => {
    const lm = parseListMarkerPrefixed('> - [x] done')!
    expect(lm.kind).toBe('checkbox')
    expect(lm.box?.start).toBe('> - '.length)
  })
  it('matches plain parseListMarker when there is no prefix', () => {
    const lm = parseListMarkerPrefixed('1. top')!
    expect(lm.kind).toBe('ordered')
    expect(lm.markerStart).toBe(0)
  })
  it('does NOT strip a `>` with no space after it (not a real quote — agrees with the renderer)', () => {
    expect(parseListMarkerPrefixed('>- x')).toBeNull() // `>-` isn't a quoted list; renderer shows it raw
  })
})
