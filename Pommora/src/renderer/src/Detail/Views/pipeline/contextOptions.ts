// The one context-tier → pickable-options mapping (table cell pickers, the FilterPane's chip
// fields). Pure: no fs, no React.
import type { NexusTree } from '@shared/types'

export interface ContextOption {
  value: string
  label: string
  color?: string
}

/** A tier level's pickable contexts — id/title(/color) off the live tree. */
export function contextOptionsFor(level: number, tree: NexusTree): ContextOption[] {
  const list =
    level === 1 ? tree.contexts.areas : level === 2 ? tree.contexts.topics : tree.contexts.projects
  return list.map((c) => ({
    value: c.id,
    label: c.title,
    ...('color' in c && c.color ? { color: c.color } : {}),
  }))
}
