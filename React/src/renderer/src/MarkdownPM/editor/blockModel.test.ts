import { describe, it, expect } from 'vitest'
import { blockAt, blockStarts, type Block } from './blockModel'

const slice = (doc: string, b: Block | null): string | null => (b ? doc.slice(b.from, b.to) : null)

describe('blockAt', () => {
  it('heading grabs its whole section', () => {
    const doc = '# A\nbody\nmore\n# B\nx'
    const b = blockAt(doc, 0)
    expect(b?.kind).toBe('heading')
    expect(slice(doc, b)).toBe('# A\nbody\nmore')
  })

  it('a body-less heading is one line', () => {
    const doc = '# A\n# B\nx'
    const b = blockAt(doc, 0)
    expect(b?.kind).toBe('heading')
    expect(slice(doc, b)).toBe('# A')
  })

  it('list grabs the whole contiguous run including nested items', () => {
    const doc = 'para\n\n- one\n- two\n  - nested\n- three\n\nafter'
    const b = blockAt(doc, doc.indexOf('- two'))
    expect(b?.kind).toBe('list')
    expect(slice(doc, b)).toBe('- one\n- two\n  - nested\n- three')
  })

  it('callout box wins over its inner list (box-first precedence)', () => {
    const doc = '> [!note] Head\n> body\n> - inner item\nafter'
    const b = blockAt(doc, doc.indexOf('- inner item'))
    expect(b?.kind).toBe('callout')
    expect(slice(doc, b)).toBe('> [!note] Head\n> body\n> - inner item')
  })

  it('a plain (untagged) blockquote is a blockquote block', () => {
    const doc = 'p\n\n> quote one\n> quote two\nafter'
    const b = blockAt(doc, doc.indexOf('quote two'))
    expect(b?.kind).toBe('blockquote')
    expect(slice(doc, b)).toBe('> quote one\n> quote two')
  })

  it('a fenced code block is one block, and a `#` inside it is not mis-read as a heading', () => {
    const doc = 'p\n\n```\n# not a heading\ncode\n```\nafter'
    const b = blockAt(doc, doc.indexOf('# not a heading'))
    expect(b?.kind).toBe('code')
    expect(slice(doc, b)).toBe('```\n# not a heading\ncode\n```')
  })

  it('a thematic break is its own block and is never absorbed by an adjacent paragraph', () => {
    const doc = 'para one\n---\npara two'
    expect(blockAt(doc, 0)?.kind).toBe('paragraph')
    expect(slice(doc, blockAt(doc, 0))).toBe('para one') // stops at the hr
    const hr = blockAt(doc, doc.indexOf('---'))
    expect(hr?.kind).toBe('hr')
    expect(slice(doc, hr)).toBe('---')
    expect(slice(doc, blockAt(doc, doc.indexOf('para two')))).toBe('para two')
  })

  it('paragraph is the run of non-blank lines, bounded by a blank line', () => {
    const doc = 'line one\nline two\n\nother'
    const b = blockAt(doc, 0)
    expect(b?.kind).toBe('paragraph')
    expect(slice(doc, b)).toBe('line one\nline two')
  })

  it('a paragraph stops at an adjacent heading with no blank between', () => {
    const doc = 'intro text\n# Heading\nbody'
    expect(slice(doc, blockAt(doc, 0))).toBe('intro text')
  })

  it('a blank line owns no block', () => {
    const doc = 'a\n\nb'
    expect(blockAt(doc, 2)).toBeNull()
  })

  it('to is exclusive of the trailing newline', () => {
    const doc = 'para\n\nnext'
    const b = blockAt(doc, 0)
    expect(doc[b!.to]).toBe('\n')
  })

  it('a table region is one block', () => {
    // A pipe-less line glued directly to a table is a GFM 1-cell row, so a real table sits before a blank.
    const doc = 'p\n\n| a | b |\n| - | - |\n| 1 | 2 |\n\nafter'
    const b = blockAt(doc, doc.indexOf('| 1 | 2 |'))
    expect(b?.kind).toBe('table')
    expect(slice(doc, b)).toBe('| a | b |\n| - | - |\n| 1 | 2 |')
  })

  it('a multi-line list item keeps its wrapped body in the list block', () => {
    const doc = '- item one\n  wrapped text\n- item two'
    expect(slice(doc, blockAt(doc, 0))).toBe(doc) // from the marker
    const wrap = blockAt(doc, doc.indexOf('wrapped'))
    expect(wrap?.kind).toBe('list') // the wrapped line is the list, not an orphan paragraph
    expect(slice(doc, wrap)).toBe(doc)
  })

  it('an ordered list item keeps its continuation', () => {
    const doc = '1. first\n   continues\n2. second'
    const b = blockAt(doc, doc.indexOf('continues'))
    expect(b?.kind).toBe('list')
    expect(slice(doc, b)).toBe(doc)
  })

  it('a bare indented line with no marker above is a paragraph, not a list', () => {
    const doc = 'intro\n  indented continuation'
    const b = blockAt(doc, 0)
    expect(b?.kind).toBe('paragraph')
    expect(slice(doc, b)).toBe(doc)
  })

  it('blank-separated list items split into separate blocks (V1 decision, pinned)', () => {
    const doc = '- a\n\n- b'
    expect(slice(doc, blockAt(doc, 0))).toBe('- a')
    expect(slice(doc, blockAt(doc, doc.indexOf('- b')))).toBe('- b')
  })

  it('an unclosed code fence at EOF is one code block', () => {
    const doc = 'p\n\n```\ncode\nmore'
    const b = blockAt(doc, doc.indexOf('code'))
    expect(b?.kind).toBe('code')
    expect(slice(doc, b)).toBe('```\ncode\nmore')
  })

  it('duplicate heading text resolves each section by offset, not name', () => {
    const doc = '# Dup\nbody1\n# Dup\nbody2'
    expect(slice(doc, blockAt(doc, 0))).toBe('# Dup\nbody1')
    expect(slice(doc, blockAt(doc, doc.lastIndexOf('# Dup')))).toBe('# Dup\nbody2')
  })

  it('adjacent callouts box separately (per-head detection)', () => {
    const doc = '> [!note] First\n> a\n> [!tip] Second\n> b'
    expect(slice(doc, blockAt(doc, doc.indexOf('> a')))).toBe('> [!note] First\n> a')
    expect(slice(doc, blockAt(doc, doc.indexOf('Second')))).toBe('> [!tip] Second\n> b')
  })

  it('block math with an internal blank splits — known V1 gap, pinned', () => {
    const doc = '$$\nx=1\n\ny=2\n$$'
    expect(blockAt(doc, 0)?.kind).toBe('paragraph')
    expect(slice(doc, blockAt(doc, 0))).toBe('$$\nx=1')
  })

  it('blockStarts marks the heading line and each block inside its section, with kinds', () => {
    const doc = '# H\npara one\npara two\n\n- a\n- b\n\nplain'
    expect(blockStarts(doc)).toEqual([
      { from: 0, kind: 'heading' },
      { from: 4, kind: 'paragraph' },
      { from: 23, kind: 'list' },
      { from: 32, kind: 'paragraph' }
    ])
  })
})
