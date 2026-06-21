import { describe, it, expect } from 'vitest'
import { toggleInline, setHeading, setList, setBlock, type FormatEdit } from './format'

function apply(doc: string, edit: FormatEdit): string {
  let out = doc
  for (const c of [...edit.changes].sort((a, b) => b.from - a.from)) {
    out = out.slice(0, c.from) + c.insert + out.slice(c.to)
  }
  return out
}

describe('toggleInline', () => {
  it('wraps a selection', () => {
    expect(apply('hello', toggleInline('hello', 0, 5, 'bold'))).toBe('**hello**')
  })
  it('unwraps when the selection already sits inside the mark', () => {
    const doc = 'a **bold** b'
    expect(apply(doc, toggleInline(doc, 5, 5, 'bold'))).toBe('a bold b')
  })
  it('link wraps with an empty url ready for typing', () => {
    expect(apply('site', toggleInline('site', 0, 4, 'link'))).toBe('[site]()')
  })
  it('connection wraps the selection in [[ ]], and unwraps from inside', () => {
    expect(apply('Page', toggleInline('Page', 0, 4, 'connection'))).toBe('[[Page]]')
    const doc = 'a [[Page]] b'
    expect(apply(doc, toggleInline(doc, 5, 5, 'connection'))).toBe('a Page b')
  })
})

describe('setHeading', () => {
  it('sets a level', () => {
    expect(apply('hello', setHeading('hello', 0, 2))).toBe('## hello')
  })
  it('level 0 clears an existing heading', () => {
    expect(apply('## hello', setHeading('## hello', 0, 0))).toBe('hello')
  })
  it('replaces a list marker rather than stacking', () => {
    expect(apply('- item', setHeading('- item', 0, 1))).toBe('# item')
  })
})

describe('setList', () => {
  it('adds a bullet', () => {
    expect(apply('item', setList('item', 0, 'bullet'))).toBe('- item')
  })
  it('re-applying the same kind clears it', () => {
    expect(apply('- item', setList('- item', 2, 'bullet'))).toBe('item')
  })
  it('switches ordered → task', () => {
    expect(apply('1. item', setList('1. item', 3, 'task'))).toBe('- [ ] item')
  })
})

describe('setBlock', () => {
  it('toggles a blockquote on and off', () => {
    expect(apply('text', setBlock('text', 0, 'quote'))).toBe('> text')
    expect(apply('> text', setBlock('> text', 2, 'quote'))).toBe('text')
  })
  it('fences a line as code', () => {
    expect(apply('x = 1', setBlock('x = 1', 0, 'code'))).toBe('```\nx = 1\n```')
  })
})
