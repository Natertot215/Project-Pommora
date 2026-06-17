// Selection reconciliation against a freshly-read tree. After a mutation refetch, the prior
// selection can be stale: the entity was deleted (its id is gone) or renamed/moved (its id
// survives but its path changed). Pure + dependency-free so it's unit-tested without a DOM.

import type { NexusTree, PageNode, PageTypeNode, SelectionState } from '@shared/types'

/** Every PageType across ungrouped vaults + user sections. */
function allVaults(tree: NexusTree): PageTypeNode[] {
  return [...tree.vaults, ...tree.userSections.flatMap((s) => s.vaults)]
}

/** Every page in the tree (vault-direct + collection-direct + set pages). */
function allPages(tree: NexusTree): PageNode[] {
  const pages: PageNode[] = []
  for (const v of allVaults(tree)) {
    pages.push(...v.pages)
    for (const c of v.collections) {
      pages.push(...c.pages)
      for (const s of c.sets) pages.push(...s.pages)
    }
  }
  return pages
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
      return selection
    case 'vault':
      return allVaults(tree).some((v) => v.id === selection.id) ? selection : { kind: 'none' }
    case 'page': {
      const page = allPages(tree).find((p) => p.id === selection.id)
      if (!page) return { kind: 'none' }
      return page.path === selection.path ? selection : { kind: 'page', id: page.id, path: page.path }
    }
  }
}
