// Resolved cell + group-header text for the table render (Part 2 A). Turns a row's raw PropertyValue
// into display text — option VALUES become their schema label, tier/context ULIDs become Context
// titles — so no raw id ever reaches screen. The type-aware chip rendering (Task 7) resolves through
// the same helpers. Pure: no React.

import type { PropertyDefinition } from '@shared/properties'
import type { CollectionNode, ResolvedGroup, SetNode, ViewRow } from '@shared/types'
import type { SavedView } from '@shared/views'
import { resolveFieldValue } from '../pipeline/value'
import type { ResolveContext } from './resolveContext'

/** A select/status option for a stored value, via the column's schema def — `{ label, color? }`,
 *  undefined if the column isn't a select/status or the value is unknown. Chip cells read `color`;
 *  text resolution reads `label`. */
export function findOption(
  columnId: string,
  value: string,
  schema: PropertyDefinition[]
): { label: string; color?: string } | undefined {
  const def = schema.find((d) => d.id === columnId)
  return (
    def?.select_options?.find((o) => o.value === value) ??
    def?.status_groups?.flatMap((g) => g.options).find((o) => o.value === value)
  )
}

/** A select/status option's label for a stored value (undefined if unknown). */
export function optionLabel(columnId: string, value: string, schema: PropertyDefinition[]): string | undefined {
  return findOption(columnId, value, schema)?.label
}

/** A row's cell as display text: option values → labels, tier/context ULIDs → Context titles, the
 *  rest stringified. Resolved through the context so no raw id reaches screen. */
export function cellText(row: ViewRow, columnId: string, ctx: ResolveContext): string {
  const v = resolveFieldValue(row, columnId)
  switch (v.kind) {
    case 'select':
    case 'status':
      return optionLabel(columnId, v.value, ctx.schema) ?? v.value
    case 'multiSelect':
      return v.value.map((val) => optionLabel(columnId, val, ctx.schema) ?? val).join(', ')
    case 'context':
      return v.value.map((id) => ctx.contextsById.get(id)?.title ?? id).join(', ')
    case 'url':
    case 'datetime':
      return v.value
    case 'number':
      return String(v.value)
    case 'checkbox':
      return v.value ? '✓' : ''
    case 'file':
      return v.value.map((f) => f.path.split('/').pop() ?? f.path).join(', ')
    default:
      return ''
  }
}

/** A group header's display label: a structural Set group → its title; a property group → the grouped
 *  property's option label for the bucket (checkbox buckets → On/Off), the raw key as last resort; the
 *  no-value band → '' (rendered headerless). */
export function groupLabel(
  group: ResolvedGroup,
  view: SavedView,
  ctx: ResolveContext,
  setNames: Map<string, string>
): string {
  if (group.kind === 'ungrouped') return ''
  if (group.kind === 'structural-set') return setNames.get(group.key) ?? group.key
  const groupPropId = view.group?.kind === 'property' ? view.group.property_id : undefined
  if (!groupPropId) return group.key
  // 'true'/'false' are the checkbox bucket keys minted by bucketKey, not arbitrary strings.
  const rawFallback = group.key === 'true' ? 'On' : group.key === 'false' ? 'Off' : group.key
  return optionLabel(groupPropId, group.key, ctx.schema) ?? rawFallback
}

/** One walk of a container's Set subtree → an id-keyed map (names / icons / paths below). */
function buildSetMap<T>(source: CollectionNode | SetNode, pick: (s: SetNode) => T): Map<string, T> {
  const m = new Map<string, T>()
  const walk = (sets: SetNode[] | undefined): void => {
    for (const s of sets ?? []) {
      m.set(s.id, pick(s))
      walk(s.sets)
    }
  }
  walk(source.sets)
  return m
}

/** Set id → title across a container's Set subtree (for structural group headers). */
export const buildSetNames = (source: CollectionNode | SetNode): Map<string, string> =>
  buildSetMap(source, (s) => s.title)

/** Set id → its per-entity icon (a symbol name, or undefined ⇒ the folder default) across a container's
 *  Set subtree — for structural group-header glyphs (E-3). */
export const buildSetIcons = (source: CollectionNode | SetNode): Map<string, string | undefined> =>
  buildSetMap(source, (s) => s.icon)

/** Set id → its real path — the band-drag reparent commit needs paths for moveSet (a ResolvedGroup
 *  carries only the id). */
export const buildSetPaths = (source: CollectionNode | SetNode): Map<string, string> =>
  buildSetMap(source, (s) => s.path)
