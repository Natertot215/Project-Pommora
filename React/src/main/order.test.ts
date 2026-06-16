import { describe, it, expect } from 'vitest'
import { resolveOrder } from './order'

const mk = (id: string, title: string): { id: string; title: string } => ({ id, title })

describe('resolveOrder', () => {
  it('id-asc fallback when no persisted order', () => {
    const r = resolveOrder([mk('b', 'Z'), mk('a', 'Y')], undefined)
    expect(r.map((x) => x.id)).toEqual(['a', 'b'])
  })

  it('title fallback when requested (adopted entities)', () => {
    const r = resolveOrder([mk('z9', 'Apple'), mk('a1', 'Zebra')], undefined, 'title')
    expect(r.map((x) => x.title)).toEqual(['Apple', 'Zebra'])
  })

  it('honors persisted order, then appends unreferenced by title', () => {
    const r = resolveOrder([mk('a', 'A'), mk('b', 'B'), mk('c', 'C')], ['c', 'a'])
    expect(r.map((x) => x.id)).toEqual(['c', 'a', 'b'])
  })

  it('drops tombstones (ids in order but not in items)', () => {
    const r = resolveOrder([mk('a', 'A')], ['x', 'a'])
    expect(r.map((x) => x.id)).toEqual(['a'])
  })
})
