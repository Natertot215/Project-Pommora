import { describe, it, expect } from 'vitest'
import { connectionEdges } from './edges'
import { buildLinkIndex } from './resolve'

describe('connectionEdges', () => {
  const idx = buildLinkIndex([
    { id: 'target', title: 'Target' },
    { id: 'dup1', title: 'Dup' },
    { id: 'dup2', title: 'Dup' }
  ])

  it('resolves each scanned link, carrying status + multiplicity + targetId', () => {
    const edges = connectionEdges('src', 'see [[Target]] twice [[target]], [[Dup]], [[Ghost]]', idx)
    const byTitle = Object.fromEntries(edges.map((e) => [e.normalizedTitle, e]))

    expect(byTitle.target).toEqual({
      sourceId: 'src',
      normalizedTitle: 'target',
      status: 'resolved',
      targetId: 'target',
      multiplicity: 2
    })
    expect(byTitle.dup).toMatchObject({ status: 'ambiguous', multiplicity: 1 })
    expect(byTitle.dup.targetId).toBeUndefined()
    expect(byTitle.ghost).toMatchObject({ status: 'phantom' })
    expect(byTitle.ghost.targetId).toBeUndefined()
  })

  it('returns [] for a body with no links', () => {
    expect(connectionEdges('src', 'plain text', idx)).toEqual([])
  })
})
