// Selection reconciliation against a freshly-read tree. After a mutation refetch, the prior
// selection can be stale: the entity was deleted (its id is gone) or renamed/moved (its id
// survives but its path changed). Pure + dependency-free so it's unit-tested without a DOM.

import type { AreaNode, CollectionNode, NexusTree, PageNode, ProjectNode, SelectionState, SetNode, TopicNode } from '@shared/types'

/** Every top Collection across ungrouped + user sections. */
export function allCollections(tree: NexusTree): CollectionNode[] {
  return [...(tree.collections ?? []), ...tree.userSections.flatMap((s) => s.collections ?? [])]
}

/** Every Set at any depth under the tree's Collections (the recursive flatten). */
export function allSets(tree: NexusTree): SetNode[] {
  const out: SetNode[] = []
  const walk = (sets: SetNode[] | undefined): void => {
    for (const s of sets ?? []) {
      out.push(s)
      walk(s.sets)
    }
  }
  for (const c of allCollections(tree)) walk(c.sets)
  return out
}

/** Every page in the tree (Collection-direct + every nested Set's pages). */
export function allPages(tree: NexusTree): PageNode[] {
  const pages: PageNode[] = []
  for (const c of allCollections(tree)) pages.push(...c.pages)
  for (const s of allSets(tree)) pages.push(...s.pages)
  return pages
}

/** Every context leaf across the three free-standing tiers (Areas + Topics + Projects). */
export function allContexts(tree: NexusTree): (AreaNode | TopicNode | ProjectNode)[] {
  return [...tree.contexts.areas, ...tree.contexts.topics, ...tree.contexts.projects]
}

/** One tree flatten, reusable across many reconciles — the shape `applyTree` builds ONCE per push to
 *  reconcile the selection plus every tab's target + history without a per-call tree walk. */
export interface ReconcileIndex {
  contexts: ReadonlySet<string>
  collections: ReadonlySet<string>
  sets: ReadonlyMap<string, string>
  pages: ReadonlyMap<string, string>
}

export function buildReconcileIndex(tree: NexusTree): ReconcileIndex {
  return {
    contexts: new Set(allContexts(tree).map((c) => c.id)),
    collections: new Set(allCollections(tree).map((c) => c.id)),
    sets: new Map(allSets(tree).map((s) => [s.id, s.path])),
    pages: new Map(allPages(tree).map((p) => [p.id, p.path]))
  }
}

/**
 * Reconcile `selection` against a prebuilt index. Returns the SAME reference when nothing changed
 * (so callers can skip a redundant state update); a fresh entry with the updated path when a
 * selected set/page was renamed/moved; or `{ kind: 'none' }` when the selected entity is gone.
 * Selection is id-keyed (rename-safe); only the path is refreshed.
 */
export function reconcileWith(index: ReconcileIndex, selection: SelectionState): SelectionState {
  switch (selection.kind) {
    case 'none':
    case 'homepage':
      // Homepage is a singleton (always present) — never reconciled away.
      return selection
    case 'context':
      return index.contexts.has(selection.id) ? selection : { kind: 'none' }
    case 'collection':
      return index.collections.has(selection.id) ? selection : { kind: 'none' }
    case 'set': {
      const path = index.sets.get(selection.id)
      if (path === undefined) return { kind: 'none' }
      return path === selection.path ? selection : { kind: 'set', id: selection.id, path }
    }
    case 'page': {
      const path = index.pages.get(selection.id)
      if (path === undefined) return { kind: 'none' }
      return path === selection.path ? selection : { kind: 'page', id: selection.id, path }
    }
  }
}

/** One-shot reconcile (a single selection against a tree) — Back/Forward steps and click-time pin
 *  resolution. Anything reconciling MANY refs per push builds the index once instead. */
export function reconcileSelection(tree: NexusTree, selection: SelectionState): SelectionState {
  return reconcileWith(buildReconcileIndex(tree), selection)
}
