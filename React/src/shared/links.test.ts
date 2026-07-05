import { describe, it, expect } from 'vitest'
import { linkDomain, normalizeLinkUrl, isValidLink, isHttpLink } from './links'

describe('linkDomain', () => {
  it('returns the bare host', () => {
    expect(linkDomain('https://example.com/some/path?q=1')).toBe('example.com')
  })
  it('drops a leading www.', () => {
    expect(linkDomain('https://www.github.com/rust-lang/rust')).toBe('github.com')
  })
  it('keeps a non-www subdomain', () => {
    expect(linkDomain('https://docs.rust-lang.org/book')).toBe('docs.rust-lang.org')
  })
  it('normalizes a schemeless URL before parsing', () => {
    expect(linkDomain('www.example.com/x')).toBe('example.com')
  })
  it('lowercases nothing it need not, but strips only the www label', () => {
    expect(linkDomain('https://wwwfoo.example.com')).toBe('wwwfoo.example.com')
  })
  it('falls back to the trimmed input when unparseable', () => {
    expect(linkDomain('  not a url  ')).toBe('not a url')
  })
})

describe('normalizeLinkUrl (guard co-tested with the fetch path)', () => {
  it('adds https:// to a schemeless host', () => {
    expect(normalizeLinkUrl('example.com')).toBe('https://example.com')
  })
  it('leaves an explicit scheme alone', () => {
    expect(normalizeLinkUrl('http://example.com')).toBe('http://example.com')
    expect(normalizeLinkUrl('mailto:a@b.com')).toBe('mailto:a@b.com')
  })
})

describe('isValidLink (the open gate)', () => {
  it('accepts a well-formed http(s) URL', () => {
    expect(isValidLink('https://example.com')).toBe(true)
    expect(isValidLink('example.com/path')).toBe(true)
  })
  it('accepts a plausible mailto', () => {
    expect(isValidLink('mailto:a@b.com')).toBe(true)
  })
  it('rejects a hostless or spaced string', () => {
    expect(isValidLink('not a url')).toBe(false)
    expect(isValidLink('localhost')).toBe(false)
  })
})

describe('isHttpLink (the title-fetch gate — http(s) only)', () => {
  it('accepts what the fetcher can hit', () => {
    expect(isHttpLink('https://example.com')).toBe(true)
    expect(isHttpLink('example.com/path')).toBe(true)
  })
  it('rejects a mailto — valid to open, but no page to fetch', () => {
    expect(isHttpLink('mailto:a@b.com')).toBe(false)
  })
  it('rejects garbage the same as isValidLink', () => {
    expect(isHttpLink('not a url')).toBe(false)
  })
})
