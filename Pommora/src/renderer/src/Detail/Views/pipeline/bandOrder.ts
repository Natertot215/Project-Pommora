// Applies a view's manual structural band order (SavedView.group_order — one flat set-id array
// covering every nesting level) to resolved groups. Listed sets lead in array order, unlisted
// sets trail in fs order, the ungrouped tail stays pinned last, non-structural groups pass
// through untouched. Pure: no fs, no React.

import type { ResolvedGroup } from '@shared/types'

export function orderGroups(groups: ResolvedGroup[], groupOrder: string[] | undefined): ResolvedGroup[] {
  if (!groupOrder || groupOrder.length === 0) return groups
  const pos = new Map(groupOrder.map((id, i) => [id, i]))
  const walk = (level: ResolvedGroup[]): ResolvedGroup[] => {
    const recursed = level.map((g) => (g.children ? { ...g, children: walk(g.children) } : g))
    const sets = recursed.filter((g) => g.kind === 'structural-set')
    if (sets.length === 0) return recursed
    const listed = sets
      .filter((g) => pos.has(g.key))
      .sort((a, b) => (pos.get(a.key) ?? 0) - (pos.get(b.key) ?? 0))
    const unlisted = sets.filter((g) => !pos.has(g.key))
    const rest = recursed.filter((g) => g.kind !== 'structural-set')
    return [...listed, ...unlisted, ...rest]
  }
  return walk(groups)
}
