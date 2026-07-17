import type { CollectionNode, NexusTree, SelectionState, SetNode } from '@shared/types'
import type { SelectTarget, TrailEntry } from '../../store'
import { findContext } from '../Scope'

/** One breadcrumb segment. `onClick` absent ⇒ the current/non-navigable segment; `ghost` ⇒ the
 *  dimmed last-visited-page "forward" crumb you can click to jump back into. */
export interface Crumb {
  key: string
  title: string
  ghost?: boolean
  onClick?: () => void
}

const basename = (path: string): string => (path.split('/').pop() ?? path).replace(/\.md$/, '')

const allCollections = (tree: NexusTree): CollectionNode[] => [
  ...(tree.collections ?? []),
  ...tree.userSections.flatMap((s) => s.collections ?? []),
]

/** The collection + set-chain leading to a node id (a container, or the container holding a page). */
export function chainOf(
  tree: NexusTree,
  id: string,
): { collection: CollectionNode; sets: SetNode[] } | null {
  const inSets = (sets: SetNode[] | undefined, acc: SetNode[]): SetNode[] | null => {
    for (const s of sets ?? []) {
      if (s.id === id || s.pages.some((p) => p.id === id)) return [...acc, s]
      const deep = inSets(s.sets, [...acc, s])
      if (deep) return deep
    }
    return null
  }
  for (const col of allCollections(tree)) {
    if (col.id === id || col.pages.some((p) => p.id === id)) return { collection: col, sets: [] }
    const path = inSets(col.sets, [])
    if (path) return { collection: col, sets: path }
  }
  return null
}

/** Immediate container id holding a page (its last set, or the collection if directly in one). */
export function pageContainerId(tree: NexusTree, pageId: string): string | null {
  const chain = chainOf(tree, pageId)
  if (!chain) return null
  return chain.sets.length ? chain.sets[chain.sets.length - 1].id : chain.collection.id
}

/**
 * Breadcrumb segments for the open view. Collection + depth-1 Set crumbs navigate (they have detail
 * surfaces); deeper Sub-Set crumbs are plain; the current segment has no action. A container view
 * appends the dimmed ghost crumb for the page you last backed out of (forward affordance).
 */
export function subfieldCrumbs(
  tree: NexusTree | null,
  selection: SelectionState,
  trail: Record<string, TrailEntry>,
  select: (target: SelectTarget) => void,
): Crumb[] {
  if (!tree) return []
  switch (selection.kind) {
    case 'none':
      return []
    case 'homepage':
      return [{ key: 'home', title: tree.nexus.name }]
    case 'context': {
      const ctx = findContext(tree, selection.id)
      return ctx ? [{ key: selection.id, title: ctx.name }] : []
    }
    case 'collection':
    case 'set': {
      const chain = chainOf(tree, selection.id)
      if (!chain) return []
      const crumbs: Crumb[] = [
        {
          key: chain.collection.id,
          title: chain.collection.title,
          onClick:
            selection.kind === 'set'
              ? () => select({ kind: 'collection', id: chain.collection.id })
              : undefined,
        },
      ]
      chain.sets.forEach((s, i) => {
        const isCurrent = i === chain.sets.length - 1
        const isDepth1 = i === 0
        crumbs.push({
          key: s.id,
          title: s.title,
          onClick:
            !isCurrent && isDepth1
              ? () => select({ kind: 'set', id: s.id, path: s.path })
              : undefined,
        })
      })
      const ghost = trail[selection.id]
      if (ghost) {
        crumbs.push({
          key: `ghost-${ghost.id}`,
          title: ghost.title,
          ghost: true,
          onClick: () => select({ kind: 'page', id: ghost.id, path: ghost.path }),
        })
      }
      return crumbs
    }
    case 'page': {
      const chain = chainOf(tree, selection.id)
      if (!chain) return [{ key: selection.id, title: basename(selection.path) }]
      const crumbs: Crumb[] = [
        {
          key: chain.collection.id,
          title: chain.collection.title,
          onClick: () => select({ kind: 'collection', id: chain.collection.id }),
        },
      ]
      chain.sets.forEach((s, i) => {
        const isDepth1 = i === 0
        crumbs.push({
          key: s.id,
          title: s.title,
          onClick: isDepth1 ? () => select({ kind: 'set', id: s.id, path: s.path }) : undefined,
        })
      })
      crumbs.push({ key: selection.id, title: basename(selection.path) })
      return crumbs
    }
  }
}
