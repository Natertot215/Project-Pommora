// The one context-tier → pickable-options mapping (table cell pickers, the FilterPane's chip
// fields). Pure: no fs, no React.
import type { NexusTree } from '@shared/types'

export interface ContextOption {
  value: string
  label: string
  color?: string
}

// The card grid calls this per tier/context value per render (eagerly, not just for an open picker),
// so return a STABLE array per (tree, level) instead of mapping the tier list every call — keyed on the
// tree object, so a tree push naturally invalidates it. Without this it allocates N fresh arrays a frame.
const tierOptionsCache = new WeakMap<NexusTree, Map<number, ContextOption[]>>()

/** A tier level's pickable contexts — id/title(/color) off the live tree, memoized per tree. */
export function contextOptionsFor(level: number, tree: NexusTree): ContextOption[] {
  let byLevel = tierOptionsCache.get(tree)
  if (!byLevel) tierOptionsCache.set(tree, (byLevel = new Map()))
  let opts = byLevel.get(level)
  if (!opts) byLevel.set(level, (opts = buildTierOptions(level, tree)))
  return opts
}

function buildTierOptions(level: number, tree: NexusTree): ContextOption[] {
  const list =
    level === 1 ? tree.contexts.areas : level === 2 ? tree.contexts.topics : tree.contexts.projects
  return list.map((c) => ({
    value: c.id,
    label: c.title,
    ...('color' in c && c.color ? { color: c.color } : {}),
  }))
}
