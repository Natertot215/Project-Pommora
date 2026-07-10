// View pipeline orchestrator. Composes the pure stages: columns (resolver) + filter → group →
// sort-within-group. VIEW-SOURCE-AGNOSTIC — `view`, `rows`, `schema`, `setTree` are all passed in,
// so a future context-dashboard embed reuses this verbatim with its own stored SavedView + a target
// ref. Never couple the view to its container or read `views[]` here. Pure: no fs, no React.

import type { PropertyDefinition } from '@shared/properties'
import type { ResolvedColumn, ResolvedGroup, ViewRow } from '@shared/types'
import type { SavedView } from '@shared/views'
import { applyFilter } from './filter'
import { orderGroups } from './bandOrder'
import { groupsStructurally, resolveGroups, type SetTreeNode } from './group'
import { makeSorter } from './sort'
import { resolveColumns } from './columns'

export function resolveView(input: {
  rows: ViewRow[]
  setTree: SetTreeNode[]
  view: SavedView
  schema: PropertyDefinition[]
  /** Per-machine manual row order (viewOrders cache) — the lowest-priority sort tiebreaker (D-5/D-6).
   *  Pass it only when the view is sorted or grouped; an unsorted, ungrouped view uses page_order. */
  manualOrder?: string[]
}): { columns: ResolvedColumn[]; groups: ResolvedGroup[] } {
  const { rows, setTree, view, schema, manualOrder } = input
  const columns = resolveColumns(view, schema)
  const filtered = applyFilter(rows, view.filter, schema)
  const sorter = makeSorter(view.sort, schema, manualOrder)
  // Location order mirrors the filesystem: group_order is preserved on the view but ignored (C-1a).
  // The mode is structural-only — and "structural" is the EFFECTIVE mode (a dead-property grouping
  // renders structurally), so the location gate + sub-group thread whenever the table draws sets.
  const structuralGrouping = groupsStructurally(view.group, schema)
  const locationOrdered = structuralGrouping && view.structural_order_mode === 'location'
  const groups = orderGroups(
    resolveGroups(
      filtered,
      view.group,
      schema,
      setTree,
      sorter,
      view.collapsed_groups,
      view.ungrouped_placement ?? 'bottom',
      structuralGrouping ? view.sub_group : undefined
    ),
    locationOrdered ? undefined : view.group_order
  )
  return { columns, groups }
}
