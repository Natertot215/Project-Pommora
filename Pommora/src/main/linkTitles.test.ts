import { describe, it, expect } from 'vitest'
import { extractTitle, makeTitleScanner } from './linkTitles'

/** Drive the streaming scanner with a pre-split byte sequence, exactly as the response `data` loop does. */
function scan(chunks: Buffer[]): string | null {
  const scanner = makeTitleScanner()
  for (const c of chunks) {
    const done = scanner.push(c)
    if (done !== undefined) return done
  }
  return scanner.end()
}

describe('extractTitle — pulling <title> out of HTML', () => {
  it('extracts a plain title', () => {
    expect(extractTitle('<html><head><title>Hello World</title></head>')).toBe('Hello World')
  })
  it('is case-insensitive and tolerates attributes on the tag', () => {
    expect(extractTitle('<TITLE data-rh="true">Tagged</TITLE>')).toBe('Tagged')
  })
  it('collapses internal whitespace and trims', () => {
    expect(extractTitle('<title>\n   Multi\n   Line  \n</title>')).toBe('Multi Line')
  })
  it('takes the first title when several exist', () => {
    expect(extractTitle('<title>First</title><title>Second</title>')).toBe('First')
  })
  it('decodes named entities', () => {
    expect(extractTitle('<title>A &amp; B &lt;3 &quot;q&quot;</title>')).toBe('A & B <3 "q"')
  })
  it('decodes numeric (decimal + hex) entities', () => {
    expect(extractTitle('<title>caf&#233; &#x1F600;</title>')).toBe('café 😀')
  })
  it('does not double-decode a literal escaped entity', () => {
    // &amp;#60; is the literal text "&#60;", not "<"
    expect(extractTitle('<title>&amp;#60;tag&amp;#62;</title>')).toBe('&#60;tag&#62;')
  })
  it('returns null for an empty title', () => {
    expect(extractTitle('<title></title>')).toBeNull()
    expect(extractTitle('<title>   </title>')).toBeNull()
  })
  it('returns null when there is no title tag', () => {
    expect(extractTitle('<html><head><meta charset="utf-8"></head>')).toBeNull()
  })
})

describe('makeTitleScanner — decoding a title across chunk boundaries', () => {
  it('reassembles multi-byte chars split across chunks (byte-by-byte worst case)', () => {
    // Café René 東京 🚀 Привет — accents, CJK, emoji (a surrogate pair), Cyrillic all multi-byte
    const title = 'Café René 東京 🚀 Привет'
    const bytes = Buffer.from(`<html><head><title>${title}</title></head>`, 'utf8')
    const perByte = Array.from({ length: bytes.length }, (_, i) => bytes.subarray(i, i + 1))
    expect(scan(perByte)).toBe(title)
  })
  it('reassembles across an arbitrary two-way split mid-character', () => {
    const bytes = Buffer.from('<title>东京タワー</title>', 'utf8')
    // split at byte 10 — lands inside a 3-byte CJK sequence
    expect(scan([bytes.subarray(0, 10), bytes.subarray(10)])).toBe('东京タワー')
  })
  it('stops and returns the title the moment </title> arrives (no need for stream end)', () => {
    const scanner = makeTitleScanner()
    expect(scanner.push(Buffer.from('<html><head><title>Done</title><body>lots more...', 'utf8'))).toBe('Done')
  })
  it('keeps reading (undefined) until the closing tag', () => {
    const scanner = makeTitleScanner()
    expect(scanner.push(Buffer.from('<html><head><title>Half', 'utf8'))).toBeUndefined()
    expect(scanner.push(Buffer.from(' Title</title>', 'utf8'))).toBe('Half Title')
  })
  it('gives up with a null once the byte cap is passed before any title', () => {
    const small = makeTitleScanner(64)
    expect(small.push(Buffer.from('x'.repeat(100), 'utf8'))).toBeNull()
  })
})
