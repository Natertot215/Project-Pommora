// Multi-key view sort. Ports Swift's ViewSortComparator — decorate-sort, select/status by schema
// option order, a type-complete property branch per PropertyType — and EXTENDS it to multiple
// criteria (divergence #1): Swift sorts by a single criterion; here `sort[]` is honored in array
// order (priority = index), each criterion compared until one breaks the tie, then stable input
// order. Pure: no fs, no React.

import type { SortCriterion } from '@shared/views'
import type { ViewRow } from '@shared/types'
import { type PropertyDefinition, RESERVED_PROPERTY_ID } from '@shared/properties'
import { declaredType, modifiedStampString, resolveFieldValue } from './value'

type SortKey = number | string
type Less = (a: SortKey, b: SortKey) => boolean

interface ResolvedCriterion {
  extract: (row: ViewRow) => SortKey
  less: Less
  ascending: boolean
}

const numericLess: Less = (a, b) => (a as number) < (b as number)
const plainLess: Less = (a, b) => (a as string) < (b as string)
// Case-insensitive, accent-sensitive — mirrors Swift's localizedCaseInsensitiveCompare.
const ciLess: Less = (a, b) =>
  (a as string).localeCompare(b as string, undefined, { sensitivity: 'accent' }) < 0

/** Map each select/status option value to its position so those types sort by the author's option
 *  order, not alphabetically (select options first, then status options flattened across the
 *  groups). Unknown/absent values rank last. Mirrors Swift optionOrderIndex. */
function optionOrderIndex(def: PropertyDefinition): Record<string, number> {
  const index: Record<string, number> = {}
  def.select_options?.forEach((o, i) => {
    index[o.value] = i
  })
  if (def.status_groups) {
    let i = Object.keys(index).length
    for (const g of def.status_groups) {
      for (const o of g.options) {
        index[o.value] = i
        i += 1
      }
    }
  }
  return index
}

function rank(row: ViewRow, propertyId: string, order: Record<string, number>): number {
  const v = resolveFieldValue(row, propertyId)
  const key = v.kind === 'select' || v.kind === 'status' ? v.value : undefined
  return key !== undefined && order[key] !== undefined ? order[key] : Number.MAX_SAFE_INTEGER
}

function numberOf(row: ViewRow, propertyId: string): number {
  const v = resolveFieldValue(row, propertyId)
  return v.kind === 'number' ? v.value : Number.NEGATIVE_INFINITY // absent sorts first ascending
}

function dateOf(row: ViewRow, propertyId: string): number {
  const v = resolveFieldValue(row, propertyId)
  if (v.kind === 'datetime') {
    const t = Date.parse(v.value)
    if (!Number.isNaN(t)) return t
  }
  return Number.NEGATIVE_INFINITY // absent / unparseable sorts first ascending (Swift .distantPast)
}

function boolRank(row: ViewRow, propertyId: string): number {
  const v = resolveFieldValue(row, propertyId)
  return v.kind === 'checkbox' && v.value ? 1 : 0 // false (0) < true (1); absent = false
}

/** Orderable text for the text-ish types `buildCriterion` routes here (url, multiSelect).
 *  select/status sort via `rank()` (schema option order) and never reach this; relation/file/
 *  absent have no orderable text → "". (Swift's sortText keeps unreachable select/status arms;
 *  dropped here.) */
function sortText(row: ViewRow, propertyId: string): string {
  const v = resolveFieldValue(row, propertyId)
  switch (v.kind) {
    case 'url':
      return v.value
    case 'multiSelect':
      return v.value.join(',')
    default:
      return ''
  }
}

/** The `_modified_at` sort preset as a timestamp; absent/unparseable → -Infinity (sorts first
 *  ascending). The modified∥created stamp resolution is shared with filter via value.ts. */
function modifiedStamp(row: ViewRow): number {
  const s = modifiedStampString(row)
  if (!s) return Number.NEGATIVE_INFINITY
  const t = Date.parse(s)
  return Number.isNaN(t) ? Number.NEGATIVE_INFINITY : t
}

/** Resolve one criterion to an extract+less pair, or null when the property isn't sortable
 *  (unknown id, or a tier column — Swift returns nil for non-schema properties). */
function buildCriterion(c: SortCriterion, schema: PropertyDefinition[]): ResolvedCriterion | null {
  const ascending = c.direction !== 'descending'
  switch (c.property_id) {
    case RESERVED_PROPERTY_ID.title:
      return { extract: (r) => r.title, less: ciLess, ascending }
    case RESERVED_PROPERTY_ID.id:
      return { extract: (r) => r.id, less: plainLess, ascending }
    case RESERVED_PROPERTY_ID.modifiedAt:
      return { extract: modifiedStamp, less: numericLess, ascending }
  }
  switch (declaredType(c.property_id, schema)) {
    case 'select':
    case 'status': {
      const def = schema.find((d) => d.id === c.property_id)
      const order = def ? optionOrderIndex(def) : {}
      return { extract: (r) => rank(r, c.property_id, order), less: numericLess, ascending }
    }
    case 'number':
      return { extract: (r) => numberOf(r, c.property_id), less: numericLess, ascending }
    case 'datetime':
    case 'last_edited_time':
      return { extract: (r) => dateOf(r, c.property_id), less: numericLess, ascending }
    case 'checkbox':
      return { extract: (r) => boolRank(r, c.property_id), less: numericLess, ascending }
    case 'url':
    case 'multi_select':
    case 'context':
    case 'file':
      return { extract: (r) => sortText(r, c.property_id), less: ciLess, ascending }
    default:
      return null // 'tier' | undefined → not sortable
  }
}

/** Build a stable multi-key group-sorter, or null when no criterion is usable (caller keeps input
 *  order). Decorate-sort: each row's key tuple is extracted ONCE, then criteria are compared in
 *  array order (priority = index); full ties hold input order. */
export function makeSorter(
  sort: SortCriterion[] | undefined,
  schema: PropertyDefinition[],
  manualOrder?: string[]
): ((rows: ViewRow[]) => ViewRow[]) | null {
  const resolved = (sort ?? [])
    .map((c) => buildCriterion(c, schema))
    .filter((rc): rc is ResolvedCriterion => rc !== null)
  // The per-machine manual order (viewOrders) is the LOWEST-priority tiebreaker (D-6): it reorders
  // only rows already equal on every real sort key, and is the sole comparator when a view is grouped
  // but unsorted. A row absent from the manual order ranks last (appended after the placed ones).
  const manualIndex = manualOrder?.length ? new Map(manualOrder.map((id, i) => [id, i] as const)) : null
  if (resolved.length === 0 && !manualIndex) return null

  return (rows) => {
    const decorated = rows.map((row, offset) => ({
      offset,
      row,
      keys: resolved.map((rc) => rc.extract(row)),
      manual: manualIndex ? (manualIndex.get(row.id) ?? Number.MAX_SAFE_INTEGER) : 0
    }))
    decorated.sort((a, b) => {
      for (let i = 0; i < resolved.length; i++) {
        const { less, ascending } = resolved[i]
        const ka = a.keys[i]
        const kb = b.keys[i]
        if (ascending) {
          if (less(ka, kb)) return -1
          if (less(kb, ka)) return 1
        } else {
          if (less(kb, ka)) return -1
          if (less(ka, kb)) return 1
        }
      }
      if (a.manual !== b.manual) return a.manual - b.manual // manual order breaks remaining ties (D-6)
      return a.offset - b.offset // stable: input order among full ties
    })
    return decorated.map((d) => d.row)
  }
}
