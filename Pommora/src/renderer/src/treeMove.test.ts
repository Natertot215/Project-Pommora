import { describe, it, expect } from 'vitest'
import type { CollectionNode, NexusTree } from '@shared/types'
import { DEFAULT_LABELS } from '@shared/types'
import {
  insertCreatedInTree,
  patchNodeInTree,
  relocateNodeInTree,
  removeNodeInTree,
  renameNodeInTree,
  reorderChildrenInTree,
  reorderTopInTree,
} from './treeMove'

/** A two-Collection tree: Notes (with a nested Set) and Work. */
function tree(): NexusTree {
  const notes: CollectionNode = {
    kind: 'collection',
    id: 'c1',
    title: 'Notes',
    path: 'Notes',
    sets: [
      {
        kind: 'set',
        id: 's1',
        title: 'Sub',
        path: 'Notes/Sub',
        sets: [],
        pages: [{ kind: 'page', id: 'p2', title: 'B', path: 'Notes/Sub/B.md' }],
      },
    ],
    pages: [{ kind: 'page', id: 'p1', title: 'A', path: 'Notes/A.md' }],
  }
  const work: CollectionNode = {
    kind: 'collection',
    id: 'c2',
    title: 'Work',
    path: 'Work',
    sets: [],
    pages: [],
  }
  return {
    nexus: { id: 'nx', rootPath: '/x', name: 'x', profileImage: null, profileSubtitle: '' },
    homepage: { locked: false, headingIconHidden: false },
    navView: {},
    saved: [],
    contexts: { projects: [], topics: [], areas: [] },
    collections: [notes, work],
    userSections: [],
    labels: DEFAULT_LABELS,
    accent: 'lavender',
    timeFormat: 'twelveHour',
    personalization: {},
    commands: {},
    registry: [],
  }
}

describe('relocateNodeInTree', () => {
  it('moves a page to another collection, updating its path', () => {
    const t = relocateNodeInTree(tree(), 'Notes/A.md', 'Work')
    expect(t).not.toBeNull()
    expect(t?.collections[0].pages.find((p) => p.id === 'p1')).toBeUndefined()
    const moved = t?.collections[1].pages.find((p) => p.id === 'p1')
    expect(moved?.path).toBe('Work/A.md')
  })

  it('moves a page out of a nested Set into a collection root', () => {
    const t = relocateNodeInTree(tree(), 'Notes/Sub/B.md', 'Work')
    expect(t?.collections[0].sets[0].pages.find((p) => p.id === 'p2')).toBeUndefined()
    expect(t?.collections[1].pages.find((p) => p.id === 'p2')?.path).toBe('Work/B.md')
  })

  it('moves a Set with its subtree, reparenting every descendant path', () => {
    const t = relocateNodeInTree(tree(), 'Notes/Sub', 'Work')
    expect(t?.collections[0].sets).toHaveLength(0)
    const moved = t?.collections[1].sets.find((s) => s.id === 's1')
    expect(moved?.path).toBe('Work/Sub')
    expect(moved?.pages[0].path).toBe('Work/Sub/B.md')
  })

  it('returns null for a no-op (already in that parent)', () => {
    expect(relocateNodeInTree(tree(), 'Notes/A.md', 'Notes')).toBeNull()
  })

  it('returns null when the node or destination is unresolved', () => {
    expect(relocateNodeInTree(tree(), 'Notes/Ghost.md', 'Work')).toBeNull()
    expect(relocateNodeInTree(tree(), 'Notes/A.md', 'Nowhere')).toBeNull()
  })
})

describe('insertCreatedInTree', () => {
  it('appends a created context to its tier', () => {
    const t = insertCreatedInTree(
      tree(),
      { op: 'createContext', tier: 2, name: 'New' },
      { id: 'x1', path: 'Topics/Reading' },
    )
    expect(t?.contexts.topics.at(-1)).toEqual({
      id: 'x1',
      kind: 'topic',
      title: 'Reading',
      path: 'Topics/Reading',
    })
  })

  it('appends a created top-level collection', () => {
    const t = insertCreatedInTree(
      tree(),
      { op: 'createContainer', parentPath: '', kind: 'collection', name: 'New' },
      { id: 'x2', path: 'Ideas' },
    )
    expect(t?.collections.at(-1)?.title).toBe('Ideas')
    expect(t?.collections.at(-1)?.kind).toBe('collection')
  })

  it('inserts a created set under its parent collection', () => {
    const t = insertCreatedInTree(
      tree(),
      { op: 'createContainer', parentPath: 'Work', kind: 'set', name: 'New' },
      { id: 'x3', path: 'Work/Drafts' },
    )
    expect(t?.collections[1].sets.at(-1)?.path).toBe('Work/Drafts')
  })

  it('inserts a created page (title minus .md) under a nested set', () => {
    const t = insertCreatedInTree(
      tree(),
      { op: 'createPage', parentPath: 'Notes/Sub', name: 'New' },
      { id: 'x4', path: 'Notes/Sub/C.md' },
    )
    const page = t?.collections[0].sets[0].pages.at(-1)
    expect(page?.title).toBe('C')
    expect(page?.path).toBe('Notes/Sub/C.md')
  })

  it('skips optimism for a nested collection (never mislabels it as a set)', () => {
    expect(
      insertCreatedInTree(
        tree(),
        { op: 'createContainer', parentPath: 'Work', kind: 'collection', name: 'New' },
        { id: 'x6', path: 'Work/Nested' },
      ),
    ).toBeNull()
  })

  it('returns null when the parent container is unresolved', () => {
    expect(
      insertCreatedInTree(
        tree(),
        { op: 'createPage', parentPath: 'Nowhere', name: 'New' },
        { id: 'x5', path: 'Nowhere/D.md' },
      ),
    ).toBeNull()
  })
})

describe('renameNodeInTree', () => {
  it('renames a page (title + .md path)', () => {
    const t = renameNodeInTree(tree(), 'Notes/A.md', 'Alpha')
    const page = t?.collections[0].pages[0]
    expect(page?.title).toBe('Alpha')
    expect(page?.path).toBe('Notes/Alpha.md')
  })

  it('renames a set, rewriting descendant paths', () => {
    const t = renameNodeInTree(tree(), 'Notes/Sub', 'Nested')
    const set = t?.collections[0].sets[0]
    expect(set?.title).toBe('Nested')
    expect(set?.path).toBe('Notes/Nested')
    expect(set?.pages[0].path).toBe('Notes/Nested/B.md')
  })

  it('renames a context in its tier', () => {
    const base = tree()
    base.contexts.topics.push({ id: 't1', kind: 'topic', title: 'Old', path: '.nexus/2/Old' })
    const t = renameNodeInTree(base, '.nexus/2/Old', 'Fresh')
    expect(t?.contexts.topics[0]).toMatchObject({ title: 'Fresh', path: '.nexus/2/Fresh' })
  })

  it('returns null for an unknown path', () => {
    expect(renameNodeInTree(tree(), 'Ghost', 'X')).toBeNull()
  })
})

describe('removeNodeInTree', () => {
  it('removes a page from a nested set', () => {
    const t = removeNodeInTree(tree(), 'Notes/Sub/B.md')
    expect(t?.collections[0].sets[0].pages).toHaveLength(0)
  })

  it('removes a whole collection', () => {
    const t = removeNodeInTree(tree(), 'Work')
    expect(t?.collections.map((c) => c.id)).toEqual(['c1'])
  })

  it('removes a context from its tier', () => {
    const base = tree()
    base.contexts.areas.push({ id: 'a1', kind: 'area', title: 'Life', path: '.nexus/1/Life' })
    const t = removeNodeInTree(base, '.nexus/1/Life')
    expect(t?.contexts.areas).toHaveLength(0)
  })
})

describe('patchNodeInTree', () => {
  it('sets and clears an icon', () => {
    const withIcon = patchNodeInTree(tree(), 'Notes', { icon: 'book' })
    expect(withIcon?.collections[0].icon).toBe('book')
    const cleared = patchNodeInTree(withIcon as NexusTree, 'Notes', { icon: null })
    expect(cleared?.collections[0].icon).toBeUndefined()
  })

  it('sets headingIconHidden on a set', () => {
    const t = patchNodeInTree(tree(), 'Notes/Sub', { headingIconHidden: true })
    expect(t?.collections[0].sets[0].headingIconHidden).toBe(true)
  })
})

describe('reorder transforms', () => {
  it('reorderTop reorders top collections, unknown ids keep relative order at the end', () => {
    const t = reorderTopInTree(tree(), 'collection_order', ['c2'])
    expect(t.collections.map((c) => c.id)).toEqual(['c2', 'c1'])
  })

  it('reorderTop reorders a context tier', () => {
    const base = tree()
    base.contexts.projects.push(
      { id: 'p10', kind: 'project', title: 'One', path: '.nexus/3/One' },
      { id: 'p11', kind: 'project', title: 'Two', path: '.nexus/3/Two' },
    )
    const t = reorderTopInTree(base, 'project_order', ['p11', 'p10'])
    expect(t.contexts.projects.map((p) => p.id)).toEqual(['p11', 'p10'])
  })

  it("reorderChildren reorders a collection's sets", () => {
    const base = tree()
    base.collections[0].sets.push({
      kind: 'set',
      id: 's2',
      title: 'Z',
      path: 'Notes/Z',
      sets: [],
      pages: [],
    })
    const t = reorderChildrenInTree(base, 'Notes', ['s2', 's1'])
    expect(t?.collections[0].sets.map((s) => s.id)).toEqual(['s2', 's1'])
  })

  it('reorderChildren with an empty parent reorders top collections', () => {
    const t = reorderChildrenInTree(tree(), '', ['c2', 'c1'])
    expect(t?.collections.map((c) => c.id)).toEqual(['c2', 'c1'])
  })
})

describe('reparentPaths depth coverage (via rename + relocate)', () => {
  /** Notes > Sub > Deep > C.md — a page two levels down, the recursion's real test. */
  function deepTree(): NexusTree {
    const t = tree()
    t.collections[0].sets[0].sets = [
      {
        kind: 'set',
        id: 's9',
        title: 'Deep',
        path: 'Notes/Sub/Deep',
        sets: [],
        pages: [{ kind: 'page', id: 'p9', title: 'C', path: 'Notes/Sub/Deep/C.md' }],
      },
    ]
    return t
  }

  it('collection rename rewrites grandchild paths without duplicating segments', () => {
    const t = renameNodeInTree(deepTree(), 'Notes', 'Diary')
    const sub = t?.collections[0].sets[0]
    expect(sub?.path).toBe('Diary/Sub')
    expect(sub?.pages[0].path).toBe('Diary/Sub/B.md')
    expect(sub?.sets?.[0].path).toBe('Diary/Sub/Deep')
    expect(sub?.sets?.[0].pages[0].path).toBe('Diary/Sub/Deep/C.md')
  })

  it('set move rewrites nested-set descendant paths without duplicating segments', () => {
    const t = relocateNodeInTree(deepTree(), 'Notes/Sub', 'Work')
    const moved = t?.collections[1].sets.find((s) => s.id === 's1')
    expect(moved?.sets?.[0].path).toBe('Work/Sub/Deep')
    expect(moved?.sets?.[0].pages[0].path).toBe('Work/Sub/Deep/C.md')
  })
})

describe('root-level rename', () => {
  it('renames a top-level collection without corrupting the path', () => {
    const t = renameNodeInTree(tree(), 'Notes', 'Diary')
    expect(t?.collections[0].path).toBe('Diary')
    expect(t?.collections[0].title).toBe('Diary')
    expect(t?.collections[0].pages[0].path).toBe('Diary/A.md')
  })
})
