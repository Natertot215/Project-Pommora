// Pure model behind the sidebar drag behavior — no React, no DOM, so it's unit-testable.
// `buildIndex` flattens the tree into everything commit + the indicator need; `nextOrder`
// computes a sibling group's new order after a drop.

import type { CollectionNode, NexusTree, PageNode, SetNode } from '@shared/types'

export type Kind = 'collection' | 'set' | 'page' | 'area' | 'topic' | 'project'
export type Entry = {
  id: string // the entry's own id (also its key in `byId`) — lets a row identify itself
  kind: Kind
  path: string
  depth: number
  parentId: string | null
  parentPath: string | null
  pageIds: string[] // direct child pages in order ([] for non-containers)
  containerIds: string[] // direct child Sets in order — Collection→sets, Set→sub-sets ([] else)
}
export type Index = {
  byId: Map<string, Entry>
  // Top-level reorder groups (ordered ids), persisted in `.nexus/state.json`.
  collectionIds: string[]
  areaIds: string[]
  topicIds: string[]
  projectIds: string[]
}

/** Id-keyed index + top-level groups. Depths match the sidebar's rendered indent (Collection 0 →
 *  its Sets 1 → Sub-Sets 2 …; pages one deeper than their container). Contexts are leaf rows at
 *  depth 1, nested under their tier disclosure (Areas / Topics / Projects) at depth 0. */
export function buildIndex(tree: NexusTree): Index {
  const byId = new Map<string, Entry>()
  const addPages = (pages: PageNode[], parentId: string, parentPath: string, depth: number): void => {
    for (const p of pages) byId.set(p.id, { id: p.id, kind: 'page', path: p.path, depth, parentId, parentPath, pageIds: [], containerIds: [] })
  }
  const walkSet = (s: SetNode, parentId: string, parentPath: string, depth: number): void => {
    const subs = s.sets ?? []
    byId.set(s.id, { id: s.id, kind: 'set', path: s.path, depth, parentId, parentPath, pageIds: s.pages.map((p) => p.id), containerIds: subs.map((x) => x.id) })
    addPages(s.pages, s.id, s.path, depth + 1)
    for (const sub of subs) walkSet(sub, s.id, s.path, depth + 1)
  }
  const walkCollection = (c: CollectionNode): void => {
    byId.set(c.id, { id: c.id, kind: 'collection', path: c.path, depth: 0, parentId: null, parentPath: null, pageIds: c.pages.map((p) => p.id), containerIds: c.sets.map((s) => s.id) })
    addPages(c.pages, c.id, c.path, 1)
    for (const s of c.sets) walkSet(s, c.id, c.path, 1)
  }
  const collections = [...(tree.collections ?? []), ...tree.userSections.flatMap((s) => s.collections ?? [])]
  for (const c of collections) walkCollection(c)

  const addContexts = (nodes: ReadonlyArray<{ id: string; path: string }>, kind: Kind): string[] => {
    for (const n of nodes) byId.set(n.id, { id: n.id, kind, path: n.path, depth: 1, parentId: null, parentPath: null, pageIds: [], containerIds: [] })
    return nodes.map((n) => n.id)
  }
  return {
    byId,
    collectionIds: collections.map((c) => c.id),
    areaIds: addContexts(tree.contexts.areas, 'area'),
    topicIds: addContexts(tree.contexts.topics, 'topic'),
    projectIds: addContexts(tree.contexts.projects, 'project')
  }
}

/** A sibling group's order after dropping `draggedId` before `beforeId` (null = append). Drops
 *  the dragged id first so a reorder lands cleanly; an unknown `beforeId` falls back to append. */
export function nextOrder(current: string[], draggedId: string, beforeId: string | null): string[] {
  const without = current.filter((id) => id !== draggedId)
  const found = beforeId ? without.indexOf(beforeId) : -1
  const at = beforeId ? (found === -1 ? without.length : found) : without.length
  return [...without.slice(0, at), draggedId, ...without.slice(at)]
}

/** A measured sidebar row's geometry, used for hit-testing the drop slot. */
export type MeasuredRow = { id: string; top: number; bottom: number; mid: number }

/** Where a dragged item lands when dropped over `over` (a same-group sibling): the id to insert
 *  before (null = append) + the y-edge for the insertion line. Top half drops before `over`;
 *  bottom half drops after it — skipping the dragged id so "after" can't resolve to itself and
 *  append to the bottom. The single source for the slot math every reorder branch shares. */
export function slotInGroup(
  group: string[],
  over: MeasuredRow,
  clientY: number,
  draggedId: string
): { beforeId: string | null; edge: number } {
  const before = clientY < over.mid
  const pos = group.indexOf(over.id)
  const beforeId = before ? over.id : group.slice(pos + 1).find((id) => id !== draggedId) ?? null
  return { beforeId, edge: before ? over.top : over.bottom }
}

/** The container (Collection or Set) a dragged Set would join, resolved from whatever row the
 *  pointer is over: the Collection/Set itself for a container header, a hovered Set's parent
 *  (reorder beside it), or a hovered page's parent container. Returns null for a context — a Set
 *  may only live inside a Collection or another Set. The caller guards against self/descendant
 *  drops (cycles). */
export function setContainerOf(entry: Entry, idx: Index): Entry | null {
  switch (entry.kind) {
    case 'collection':
      return entry
    case 'set':
      return entry.parentId ? idx.byId.get(entry.parentId) ?? null : null
    case 'page': {
      const parent = entry.parentId ? idx.byId.get(entry.parentId) ?? null : null
      if (!parent) return null
      return parent.kind === 'collection' || parent.kind === 'set' ? parent : null
    }
    default:
      return null // area / topic / project
  }
}

/** True when `targetId` is `ancestorId` itself or one of its descendants — walks parent links up
 *  from the target. Blocks dropping a Set into its own subtree. */
export function isSelfOrDescendant(targetId: string, ancestorId: string, idx: Index): boolean {
  let cur: string | null = targetId
  while (cur) {
    if (cur === ancestorId) return true
    cur = idx.byId.get(cur)?.parentId ?? null
  }
  return false
}
