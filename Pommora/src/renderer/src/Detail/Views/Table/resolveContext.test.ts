import { describe, it, expect } from 'vitest'
import { buildContextsById, buildResolveContext } from './resolveContext'
import { DEFAULT_LABELS, type NexusTree } from '@shared/types'

const tree = {
  contexts: {
    areas: [{ id: 'a1', kind: 'area', title: 'Personal', path: 'Personal', color: 'blue' }],
    topics: [{ id: 't1', kind: 'topic', title: 'Reading', path: 'Reading' }],
    projects: [{ id: 'p1', kind: 'project', title: 'Pommora', path: 'Pommora' }],
  },
  labels: DEFAULT_LABELS,
} as unknown as NexusTree

describe('buildContextsById', () => {
  it('maps each context ULID to its title (+ color for Areas)', () => {
    const m = buildContextsById(tree)
    expect(m.get('a1')).toEqual({ title: 'Personal', color: 'blue' })
    expect(m.get('t1')).toEqual({ title: 'Reading' })
    expect(m.get('p1')).toEqual({ title: 'Pommora' })
  })

  it('returns undefined for an unknown id', () => {
    expect(buildContextsById(tree).get('nope')).toBeUndefined()
  })
})

describe('buildResolveContext', () => {
  it('bundles schema + contextsById + labels', () => {
    const ctx = buildResolveContext(tree, [])
    expect(ctx.schema).toEqual([])
    expect(ctx.labels).toBe(DEFAULT_LABELS)
    expect(ctx.contextsById.get('a1')?.title).toBe('Personal')
  })
})
