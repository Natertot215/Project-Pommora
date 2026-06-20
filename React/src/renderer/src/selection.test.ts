import { describe, it, expect } from 'vitest'
import type { NexusTree, SelectionState } from '@shared/types'
import { reconcileSelection } from './selection'

/** A minimal tree with one vault holding the given top-level pages. */
function tree(pages: { id: string; path: string }[]): NexusTree {
  return {
    nexus: { id: 'nx', rootPath: '/x', name: 'x', description: '', photo: null },
    homepage: {},
    saved: [],
    contexts: { projects: [], topics: [], areas: [] },
    vaults: [
      {
        kind: 'pageType',
        id: 'v1',
        title: 'Notes',
        path: 'Notes',
        collections: [],
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
    const vault: SelectionState = { kind: 'vault', id: 'v1' }
    expect(reconcileSelection(t, page)).toBe(page)
    expect(reconcileSelection(t, none)).toBe(none)
    expect(reconcileSelection(t, vault)).toBe(vault)
  })

  it('drops a selection whose entity was deleted', () => {
    const t = tree([{ id: 'p1', path: 'Notes/A.md' }])
    expect(reconcileSelection(t, { kind: 'page', id: 'gone', path: 'Notes/Z.md' })).toEqual({ kind: 'none' })
    expect(reconcileSelection(t, { kind: 'vault', id: 'gone' })).toEqual({ kind: 'none' })
  })

  it('refreshes a selected page path after a rename/move (id stable, path changed)', () => {
    const t = tree([{ id: 'p1', path: 'Notes/Renamed.md' }])
    expect(reconcileSelection(t, { kind: 'page', id: 'p1', path: 'Notes/Old.md' })).toEqual({
      kind: 'page',
      id: 'p1',
      path: 'Notes/Renamed.md'
    })
  })

  it('finds pages nested in collections and sets (not just top-level)', () => {
    const t: NexusTree = {
      ...tree([]),
      vaults: [
        {
          kind: 'pageType',
          id: 'v1',
          title: 'Notes',
          path: 'Notes',
          pages: [],
          collections: [
            {
              kind: 'collection',
              id: 'c1',
              title: 'C',
              path: 'Notes/C',
              pages: [{ kind: 'page', id: 'cp', title: 'CP', path: 'Notes/C/CP.md' }],
              sets: [
                {
                  kind: 'set',
                  id: 's1',
                  title: 'S',
                  path: 'Notes/C/S',
                  selectable: false,
                  pages: [{ kind: 'page', id: 'sp', title: 'SP', path: 'Notes/C/S/SP.md' }]
                }
              ]
            }
          ]
        }
      ]
    }
    const setPage: SelectionState = { kind: 'page', id: 'sp', path: 'Notes/C/S/SP.md' }
    const collPage: SelectionState = { kind: 'page', id: 'cp', path: 'Notes/C/CP.md' }
    expect(reconcileSelection(t, setPage)).toBe(setPage)
    expect(reconcileSelection(t, collPage)).toBe(collPage)
  })

  it('keeps a homepage selection (singleton — always valid)', () => {
    const t = tree([])
    const home: SelectionState = { kind: 'homepage' }
    expect(reconcileSelection(t, home)).toBe(home)
  })

  it('keeps a collection selection by id; drops it when the collection is gone', () => {
    const t: NexusTree = {
      ...tree([]),
      vaults: [
        {
          kind: 'pageType',
          id: 'v1',
          title: 'Notes',
          path: 'Notes',
          pages: [],
          collections: [{ kind: 'collection', id: 'c1', title: 'C', path: 'Notes/C', pages: [], sets: [] }]
        }
      ]
    }
    expect(reconcileSelection(t, { kind: 'collection', id: 'c1' })).toEqual({ kind: 'collection', id: 'c1' })
    expect(reconcileSelection(t, { kind: 'collection', id: 'gone' })).toEqual({ kind: 'none' })
  })
})
