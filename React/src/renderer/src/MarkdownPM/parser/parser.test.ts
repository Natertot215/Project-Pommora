import { describe, it, expect } from 'vitest'
import { parse, isInsideCode, isInsideWikilink } from './index'

describe('parse (mdast seam)', () => {
  it('parses GFM into an mdast tree', () => {
    const tree = parse('# Hi\n\n- [ ] task')
    expect(tree.type).toBe('root')
    expect(tree.children.map((n) => n.type)).toContain('heading')
  })

  it('parses GFM tables (gfm extension active)', () => {
    const tree = parse('| a | b |\n|---|---|\n| 1 | 2 |')
    expect(tree.children.map((n) => n.type)).toContain('table')
  })

  it('nodes carry source offsets', () => {
    const tree = parse('# Hi')
    expect(tree.children[0].position?.start.offset).toBe(0)
  })
})

describe('isInsideWikilink', () => {
  it('true inside [[...]], false past the closer', () => {
    const t = '[[ab]] x'
    expect(isInsideWikilink(3, t)).toBe(true) // after "[[a"
    expect(isInsideWikilink(7, t)).toBe(false) // at the space past "]]"
  })

  it('resets per line (an unclosed [[ does not bleed to the next line)', () => {
    const t = 'a [[b\nc]] d'
    expect(isInsideWikilink(t.indexOf('c]]'), t)).toBe(false)
  })
})

describe('isInsideCode', () => {
  it('true between fences, false outside', () => {
    const t = 'before\n```\ncode\n```\nafter'
    expect(isInsideCode(t.indexOf('code') + 1, t)).toBe(true)
    expect(isInsideCode(t.indexOf('after') + 1, t)).toBe(false)
    expect(isInsideCode(t.indexOf('before') + 1, t)).toBe(false)
  })
})
