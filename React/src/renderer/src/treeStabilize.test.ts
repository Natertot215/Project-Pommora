import { describe, it, expect } from 'vitest'
import { stabilize } from './treeStabilize'

describe('stabilize', () => {
  const prev = {
    collections: [
      { id: 'c1', title: 'A', pages: [{ id: 'p1', title: 'One' }], sets: [] },
      { id: 'c2', title: 'B', pages: [], sets: [{ id: 's1', title: 'S' }] }
    ],
    contexts: { areas: [{ id: 'a1', title: 'Work' }], topics: [], projects: [] },
    accent: 'blue'
  }
  const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v))

  it('an echo push returns the PREVIOUS tree itself', () => {
    expect(stabilize(clone(prev), prev)).toBe(prev)
  })

  it('an unrelated change keeps the untouched container\'s identity', () => {
    const next = clone(prev)
    next.collections[1].title = 'B renamed'
    const out = stabilize(next, prev)
    expect(out).not.toBe(prev)
    expect(out.collections[0]).toBe(prev.collections[0]) // untouched container recycled
    expect(out.contexts).toBe(prev.contexts)
    expect(out.collections[1]).not.toBe(prev.collections[1])
  })

  it('a deep change rebuilds only the changed path, recycling siblings', () => {
    const next = clone(prev)
    next.collections[0].pages[0].title = 'Renamed'
    const out = stabilize(next, prev)
    expect(out.collections[1]).toBe(prev.collections[1])
    expect(out.collections[0]).not.toBe(prev.collections[0])
    expect(out.collections[0].sets).toBe(prev.collections[0].sets)
  })

  it('added / removed keys and array growth read as changes', () => {
    const next = clone(prev) as Record<string, unknown>
    next.newKey = 1
    expect(stabilize(next, prev)).not.toBe(prev)
    const shrunk = clone(prev)
    shrunk.collections.pop()
    expect(stabilize(shrunk, prev)).not.toBe(prev)
    expect(stabilize(shrunk, prev).collections[0]).toBe(prev.collections[0])
  })

  it('handles null-vs-object and primitive flips without recycling across types', () => {
    expect(stabilize(null, prev)).toBeNull()
    expect(stabilize({ a: null }, { a: {} }).a).toBeNull()
    expect(stabilize(5, prev)).toBe(5)
  })
})
