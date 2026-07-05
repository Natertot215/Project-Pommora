import { describe, it, expect } from 'vitest'
import { parseLink, serializeLink, linkDisplayText } from './linkValue'

describe('parseLink', () => {
  it('parses a bare URL as no-alias', () => {
    expect(parseLink('https://example.com')).toEqual({ url: 'https://example.com' })
  })
  it('parses a markdown link into url + alias', () => {
    expect(parseLink('[My Site](https://example.com)')).toEqual({ url: 'https://example.com', alias: 'My Site' })
  })
  it('collapses an empty alias to no alias', () => {
    expect(parseLink('[](https://example.com)')).toEqual({ url: 'https://example.com' })
  })
  it('keeps a URL that itself contains parens', () => {
    expect(parseLink('[Wiki](https://en.wikipedia.org/wiki/Foo_(bar))')).toEqual({
      url: 'https://en.wikipedia.org/wiki/Foo_(bar)',
      alias: 'Wiki'
    })
  })
  it('trims surrounding whitespace', () => {
    expect(parseLink('  https://example.com  ')).toEqual({ url: 'https://example.com' })
  })
})

describe('serializeLink', () => {
  it('writes a bare url when there is no alias', () => {
    expect(serializeLink({ url: 'https://example.com' })).toBe('https://example.com')
  })
  it('writes a markdown link when there is an alias', () => {
    expect(serializeLink({ url: 'https://example.com', alias: 'My Site' })).toBe('[My Site](https://example.com)')
  })
  it('round-trips through parse', () => {
    const raw = '[Docs](https://example.com/docs)'
    expect(serializeLink(parseLink(raw))).toBe(raw)
  })
})

describe('alias with markdown-breaking chars — escaped, never corrupts', () => {
  it('escapes `]` in the alias so the shape survives', () => {
    expect(serializeLink({ url: 'https://example.com', alias: 'Chapter [2]' })).toBe(
      '[Chapter [2\\]](https://example.com)'
    )
  })
  it('round-trips an alias containing `]`', () => {
    const v = { url: 'https://example.com', alias: 'Chapter [2]' }
    expect(parseLink(serializeLink(v))).toEqual(v)
  })
  it('round-trips an alias containing `](` and a backslash', () => {
    const v = { url: 'https://example.com', alias: 'a](b \\ c' }
    expect(parseLink(serializeLink(v))).toEqual(v)
  })
  it('the escaped form stays a url through the codec, never a select pill', () => {
    // a bare `]` in the alias would otherwise reclassify to select — the exact fixed bug
    expect(parseLink(serializeLink({ url: 'https://example.com', alias: 'TODO]' }))).toEqual({
      url: 'https://example.com',
      alias: 'TODO]'
    })
  })
})

describe('linkDisplayText — the alias always wins', () => {
  it('shows the alias regardless of the show-as look, or of a passed title', () => {
    expect(linkDisplayText('[Home](https://example.com)', 'link-url')).toBe('Home')
    expect(linkDisplayText('[Home](https://example.com)', 'link-title')).toBe('Home')
    expect(linkDisplayText('[Home](https://example.com)', 'link-title', 'Example Domain')).toBe('Home')
  })
})

describe('linkDisplayText — no alias, the look decides', () => {
  it('link-url (and the unset default) shows the full URL, never a title', () => {
    expect(linkDisplayText('https://www.example.com/x', 'link-url')).toBe('https://www.example.com/x')
    expect(linkDisplayText('https://www.example.com/x')).toBe('https://www.example.com/x')
    expect(linkDisplayText('https://www.example.com/x', 'link-url', 'Example Domain')).toBe('https://www.example.com/x')
  })
  it('link-title shows the fetched title when one is resolved', () => {
    expect(linkDisplayText('https://example.com', 'link-title', 'Example Domain')).toBe('Example Domain')
  })
  it('link-title falls back to the bare domain while loading or when the fetch failed', () => {
    expect(linkDisplayText('https://www.example.com/deep/path', 'link-title')).toBe('example.com')
    expect(linkDisplayText('https://www.example.com/deep/path', 'link-title', undefined)).toBe('example.com')
  })
})
