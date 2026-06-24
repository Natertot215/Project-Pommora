import { describe, it, expect } from 'vitest'
import type { NexusTree, SelectionState } from '@shared/types'
import { reconcileSelection } from './selection'

/** A minimal tree with one Collection holding the given top-level pages. */
function tree(pages: { id: string; path: string }[]): NexusTree {
  return {
    nexus: { id: 'nx', rootPath: '/x', name: 'x', description: '', photo: null },
    homepage: {},
    saved: [],
    contexts: { projects: [], topics: [], areas: [] },
    vaults: [],
    collections: [
      {
        kind: 'collection',
        id: 'c1',
        title: 'Notes',
        path: 'Notes',
        sets: [],
        pages: pages.map((p) => ({ kind: 'page', id: p.id, title: 'P', path: p.path }))
      }
    ],
    userSections: [],
    labels: { vaults: 'Vaults', areas: 'Areas', topics: 'Topics', projects: 'Projects', collection: 'Collection', set: 'Set' },
    accent: 'lavender'
  }
}

describe('reconcileSelection', () => {
  it('returns the SAME reference when nothing changed (no redundant update)', () => {
    const t = tree([{ id: 'p1', path: 'Notes/A.md' }])
    const page: SelectionState = { kind: 'page', id: 'p1', path: 'Notes/A.md' }
    const none: SelectionState = { kind: 'none' }
    const collection: SelectionState = { kind: 'collection', id: 'c1' }
    expect(reconcileSelection(t, page)).toBe(page)
    expect(reconcileSelection(t, none)).toBe(none)
    expect(reconcileSelection(t, collection)).toBe(collection)
  })

  it('drops a selection whose entity was deleted', () => {
    const t = tree([{ id: 'p1', path: 'Notes/A.md' }])
    expect(reconcileSelection(t, { kind: 'page', id: 'gone', path: 'Notes/Z.md' })).toEqual({ kind: 'none' })
    expect(reconcileSelection(t, { kind: 'collection', id: 'gone' })).toEqual({ kind: 'none' })
  })

  it('refreshes a selected page path after a rename/move (id stable, path changed)', () => {
    const t = tree([{ id: 'p1', path: 'Notes/Renamed.md' }])
    expect(reconcileSelection(t, { kind: 'page', id: 'p1', path: 'Notes/Old.md' })).toEqual({
      kind: 'page',
      id: 'p1',
      path: 'Notes/Renamed.md'
    })
  })

  it('finds pages nested in Sets at any depth (recursive)', () => {
    const t: NexusTree = {
      ...tree([]),
      collections: [
        {
          kind: 'collection',
          id: 'c1',
          title: 'C',
          path: 'C',
          pages: [{ kind: 'page', id: 'cp', title: 'CP', path: 'C/CP.md' }],
          sets: [
            {
              kind: 'set',
              id: 's1',
              title: 'S',
              path: 'C/S',
              pages: [{ kind: 'page', id: 'sp', title: 'SP', path: 'C/S/SP.md' }],
              sets: [
                {
                  kind: 'set',
                  id: 's2',
                  title: 'Sub',
                  path: 'C/S/Sub',
                  pages: [{ kind: 'page', id: 'subp', title: 'SubP', path: 'C/S/Sub/SubP.md' }]
                }
              ]
            }
          ]
        }
      ]
    }
    const subPage: SelectionState = { kind: 'page', id: 'subp', path: 'C/S/Sub/SubP.md' }
    const setPage: SelectionState = { kind: 'page', id: 'sp', path: 'C/S/SP.md' }
    const collPage: SelectionState = { kind: 'page', id: 'cp', path: 'C/CP.md' }
    expect(reconcileSelection(t, subPage)).toBe(subPage)
    expect(reconcileSelection(t, setPage)).toBe(setPage)
    expect(reconcileSelection(t, collPage)).toBe(collPage)
  })

  it('keeps a homepage selection (singleton — always valid)', () => {
    const t = tree([])
    const home: SelectionState = { kind: 'homepage' }
    expect(reconcileSelection(t, home)).toBe(home)
  })

  it('keeps a collection selection by id; drops it when the collection is gone', () => {
    const t = tree([])
    expect(reconcileSelection(t, { kind: 'collection', id: 'c1' })).toEqual({ kind: 'collection', id: 'c1' })
    expect(reconcileSelection(t, { kind: 'collection', id: 'gone' })).toEqual({ kind: 'none' })
  })

  it('keeps a Set selection by id at any depth; refreshes its path on move; drops it when gone', () => {
    const t: NexusTree = {
      ...tree([]),
      collections: [
        {
          kind: 'collection',
          id: 'c1',
          title: 'C',
          path: 'C',
          pages: [],
          sets: [
            {
              kind: 'set',
              id: 's1',
              title: 'S',
              path: 'C/S',
              pages: [],
              sets: [{ kind: 'set', id: 's2', title: 'Sub', path: 'C/S/Sub', pages: [] }]
            }
          ]
        }
      ]
    }
    // unchanged path → same reference
    const set1: SelectionState = { kind: 'set', id: 's1', path: 'C/S' }
    expect(reconcileSelection(t, set1)).toBe(set1)
    // a deep Sub-Set is found too, and a stale path is refreshed
    expect(reconcileSelection(t, { kind: 'set', id: 's2', path: 'C/S/Old' })).toEqual({ kind: 'set', id: 's2', path: 'C/S/Sub' })
    // gone → dropped
    expect(reconcileSelection(t, { kind: 'set', id: 'gone', path: 'C/X' })).toEqual({ kind: 'none' })
  })
})
