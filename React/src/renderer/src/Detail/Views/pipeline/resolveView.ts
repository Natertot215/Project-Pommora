// View pipeline orchestrator. Composes the pure stages: columns (resolver) + filter → group →
// sort-within-group. VIEW-SOURCE-AGNOSTIC — `view`, `rows`, `schema`, `setTree` are all passed in,
// so a future context-dashboard embed reuses this verbatim with its own stored SavedView + a target
// ref. Never couple the view to its container or read `views[]` here. Pure: no fs, no React.

import type { PropertyDefinition } from '@shared/properties'
import type { ResolvedColumn, ResolvedGroup, ViewRow } from '@shared/types'
import type { SavedView } from '@shared/views'
import { applyFilter } from './filter'
import { resolveGroups, type SetTreeNode } from './group'
import { makeSorter } from './sort'
import { resolveColumns } from './columns'

export function resolveView(input: {
  rows: ViewRow[]
  setTree: SetTreeNode[]
  view: SavedView
  schema: PropertyDefinition[]
}): { columns: ResolvedColumn[]; groups: ResolvedGroup[] } {
  const { rows, setTree, view, schema } = input
  const columns = resolveColumns(view, schema)
  const filtered = applyFilter(rows, view.filter, schema)
  const sorter = makeSorter(view.sort, schema)
  const groups = resolveGroups(filtered, view.group, schema, setTree, sorter, view.collapsed_groups)
  return { columns, groups }
}
