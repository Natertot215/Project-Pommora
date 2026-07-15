import { describe, it, expect } from 'vitest'
import type { AgendaEntry } from '@shared/types'
import { buildNavIndex, filterNav } from './navSearch'
import { makeTree } from './testTree'

const tasks: AgendaEntry[] = [{ id: 'tk1', title: 'Ship Navigation', kind: 'task' }]
const events: AgendaEntry[] = [{ id: 'ev1', title: 'Design Review', kind: 'event' }]

describe('buildNavIndex', () => {
  it('indexes homepage, contexts, collections, sets, and pages from the tree', () => {
    const index = buildNavIndex(makeTree())
    const byKind = (k: string): string[] => index.filter((e) => e.target.kind === k).map((e) => e.title)
    expect(byKind('homepage')).toEqual(['TestNexus'])
    expect(byKind('context').sort()).toEqual(['Pommora', 'Reading', 'Work'])
    expect(byKind('collection')).toEqual(['Notes'])
    expect(byKind('set')).toEqual(['Ideas'])
    expect(byKind('page').sort()).toEqual(['Alpha', 'Nested Beta'])
  })

  it('includes agenda tasks + events from the snapshot (find-only)', () => {
    const index = buildNavIndex(makeTree(), { tasks, events })
    expect(index.find((e) => e.target.kind === 'task')?.title).toBe('Ship Navigation')
    expect(index.find((e) => e.target.kind === 'event')?.title).toBe('Design Review')
  })

  it('carries a ready-to-select NavTarget with the right key', () => {
    const index = buildNavIndex(makeTree())
    const alpha = index.find((e) => e.title === 'Alpha')
    expect(alpha?.target).toEqual({ kind: 'page', id: 'p1', path: 'Notes/Alpha.md' })
    expect(alpha?.key).toBe('page:p1')
  })
})

describe('filterNav', () => {
  it('empty query returns nothing (the surface shows recents/favorites instead)', () => {
    expect(filterNav(buildNavIndex(makeTree()), '   ')).toEqual([])
  })

  it('matches page titles (page titles ARE searchable)', () => {
    const hits = filterNav(buildNavIndex(makeTree()), 'alpha')
    expect(hits.map((h) => h.title)).toContain('Alpha')
  })

  it('is case-insensitive and fuzzy (subsequence)', () => {
    const hits = filterNav(buildNavIndex(makeTree()), 'nb') // subsequence of "Nested Beta"
    expect(hits.map((h) => h.title)).toContain('Nested Beta')
  })

  it('ranks a contiguous/prefix match above a scattered subsequence', () => {
    const hits = filterNav(buildNavIndex(makeTree(), { tasks, events }), 'read')
    // "Reading" (prefix) should outrank "Design Review" (scattered r-e-a...-d)
    expect(hits[0].title).toBe('Reading')
  })

  it('drops non-matches', () => {
    const hits = filterNav(buildNavIndex(makeTree()), 'zzzzz')
    expect(hits).toEqual([])
  })

  it('respects the result cap', () => {
    const index = buildNavIndex(makeTree())
    expect(filterNav(index, 'e', 2).length).toBeLessThanOrEqual(2)
  })
})
