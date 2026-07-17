// Column resolver. Ports Swift TableColumnResolver + VisiblePropertyOrder: a two-pass visible order
// (propertyOrder VERBATIM, then unaccounted user props), default-on tiers, and a guaranteed Title.
// React divergences: emits only {id, kind} — column width and the group/sort hoist before Title are
// Part-2 render concerns; and `_modified_at` is NOT default-on (it appears only when explicitly in
// propertyOrder). Pure: no fs, no React.

import type { ColumnKind, ResolvedColumn } from '@shared/types'
import type { SavedView } from '@shared/views'
import {
  type PropertyDefinition,
  RESERVED_PROPERTY_ID,
  isReservedPropertyId,
} from '@shared/properties'

function columnKind(id: string): ColumnKind {
  switch (id) {
    case RESERVED_PROPERTY_ID.title:
      return 'title'
    case RESERVED_PROPERTY_ID.modifiedAt:
      return 'modified'
    case RESERVED_PROPERTY_ID.tier1:
    case RESERVED_PROPERTY_ID.tier2:
    case RESERVED_PROPERTY_ID.tier3:
      return 'tier'
    default:
      return 'property'
  }
}

// Reserved ids that render WITHOUT a schema def. React emits only {id, kind}, so tiers join
// title/modified here — unlike Swift, where a tier column needs a synthesized def. A non-def-less
// id in propertyOrder must be a real schema property (a stale prop_* reference is skipped).
const DEFLESS_RESERVED = new Set<string>([
  RESERVED_PROPERTY_ID.title,
  RESERVED_PROPERTY_ID.modifiedAt,
  RESERVED_PROPERTY_ID.tier1,
  RESERVED_PROPERTY_ID.tier2,
  RESERVED_PROPERTY_ID.tier3,
])

/** Visible property ids: propertyOrder verbatim (hidden honored), then unaccounted non-reserved
 *  schema props appended. Ports Swift VisiblePropertyOrder (table mode: pass 2 excludes reserved —
 *  tiers/Modified are supplied by the resolver's default-on pass instead). */
function visibleOrder(view: SavedView, schema: PropertyDefinition[]): string[] {
  const hidden = new Set(view.hidden_properties)
  const emitted = new Set<string>()
  const out: string[] = []
  const add = (id: string): void => {
    if (!emitted.has(id)) {
      emitted.add(id)
      out.push(id)
    }
  }
  for (const id of view.property_order) {
    if (hidden.has(id)) continue
    if (DEFLESS_RESERVED.has(id) || schema.some((d) => d.id === id)) add(id)
  }
  for (const d of schema) {
    if (!emitted.has(d.id) && !hidden.has(d.id) && !isReservedPropertyId(d.id)) add(d.id)
  }
  return out
}

/** Resolve a view + schema into the ordered columns Part 2 renders: visible order (pass 1+2), then
 *  default-on tiers (tier3→1, unless hidden or already placed), then a guaranteed front Title
 *  (always present, never hidden). Emits {id, kind} only. */
export function resolveColumns(view: SavedView, schema: PropertyDefinition[]): ResolvedColumn[] {
  const hidden = new Set(view.hidden_properties)
  const emitted = new Set<string>()
  const result: ResolvedColumn[] = []
  const append = (id: string): void => {
    if (emitted.has(id)) return
    emitted.add(id)
    result.push({ id, kind: columnKind(id) })
  }

  for (const id of visibleOrder(view, schema)) append(id)

  // Default-on tiers (Projects, Topics, Areas = tier3→1). NOT _modified_at — React divergence.
  for (const id of [
    RESERVED_PROPERTY_ID.tier3,
    RESERVED_PROPERTY_ID.tier2,
    RESERVED_PROPERTY_ID.tier1,
  ]) {
    if (!emitted.has(id) && !hidden.has(id)) append(id)
  }

  if (!emitted.has(RESERVED_PROPERTY_ID.title)) {
    result.unshift({ id: RESERVED_PROPERTY_ID.title, kind: 'title' })
  }
  return result
}
