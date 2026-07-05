import { describe, it, expect } from 'vitest'
import { buildPageIndex, type ConnPage } from './index'

const pages: ConnPage[] = [
  { id: '1', title: 'Project Atlas', path: 'v/Project Atlas.md' },
  { id: '2', title: 'Atlas', path: 'v/Atlas.md' },
  { id: '3', title: 'Atlas', path: 'w/Atlas.md' }, // duplicate title → ambiguous
  { id: '4', title: 'Notes', path: 'v/Notes.md' }
]

describe('resolve', () => {
  const idx = buildPageIndex(pages)
  it('resolved → exactly one holder, with its page', () => {
    const r = idx.resolve('Notes')
    expect(r.status).toBe('resolved')
    expect(r.page?.path).toBe('v/Notes.md')
  })
  it('case + whitespace insensitive', () => {
    expect(idx.resolve('  notes ').status).toBe('resolved')
  })
  it('phantom → no holder', () => {
    expect(idx.resolve('Nonexistent').status).toBe('phantom')
  })
  it('ambiguous → multiple holders', () => {
    expect(idx.resolve('Atlas').status).toBe('ambiguous')
  })
})

describe('candidates (prefix, ranked exact → shortest → A–Z)', () => {
  const idx = buildPageIndex([
    { id: '1', title: 'Project Atlas', path: 'a' },
    { id: '2', title: 'Pro', path: 'b' },
    { id: '3', title: 'Projects', path: 'c' },
    { id: '4', title: 'Notes', path: 'd' }
  ])
  it('prefix-matches and ranks exact first, then shortest, then alpha', () => {
    const titles = idx.candidates('pro').map((p) => p.title)
    expect(titles).toEqual(['Pro', 'Projects', 'Project Atlas'])
  })
  it('empty query → no candidates', () => {
    expect(idx.candidates('')).toEqual([])
  })
  it('respects the limit', () => {
    expect(idx.candidates('p', 1)).toHaveLength(1)
  })
})
