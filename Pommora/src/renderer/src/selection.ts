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

/**
 * Reconcile `selection` against `tree`. Returns the SAME reference when nothing changed (so
 * callers can skip a redundant state update); a fresh `{ kind: 'page', … }` with the updated
 * path when a selected page was renamed/moved; or `{ kind: 'none' }` when the selected entity
 * is gone. Selection is id-keyed (rename-safe); only the path is refreshed.
 */
export function reconcileSelection(tree: NexusTree, selection: SelectionState): SelectionState {
  switch (selection.kind) {
    case 'none':
    case 'homepage':
      // Homepage is a singleton (always present) — never reconciled away.
      return selection
    case 'context':
      return allContexts(tree).some((c) => c.id === selection.id) ? selection : { kind: 'none' }
    case 'collection':
      return allCollections(tree).some((c) => c.id === selection.id) ? selection : { kind: 'none' }
    case 'set': {
      // Id-keyed (rename-safe); refresh the path when a selected Set was moved/renamed.
      const set = allSets(tree).find((s) => s.id === selection.id)
      if (!set) return { kind: 'none' }
      return set.path === selection.path ? selection : { kind: 'set', id: set.id, path: set.path }
    }
    case 'page': {
      const page = allPages(tree).find((p) => p.id === selection.id)
      if (!page) return { kind: 'none' }
      return page.path === selection.path ? selection : { kind: 'page', id: page.id, path: page.path }
    }
  }
}
