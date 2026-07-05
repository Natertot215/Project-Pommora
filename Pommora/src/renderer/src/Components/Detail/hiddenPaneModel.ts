// Pure model behind the Visibility pane (HiddenPane) — no React, no DOM. One list, two zones
// (Nathan's spec): CONTEXTS on top — a static, fixed-order block whose rows ghost in place when
// hidden, never relocating; then the properties as a single run — the shown rows in view order,
// the hidden rows ghosted after them in collection order, NO heading between. Cross-zone drags
// carry the drag language: INTO the shown zone lands at a slot (a drop line — the position writes
// the view order), into the hidden zone just hides (an area highlight, no line — the hidden
// order is derived, never authored). Title appears nowhere: it can't hide, and its reorder
// belongs to the table's column drag.

import type { MeasuredRow } from '@renderer/Sidebar/sidebarDndModel'
import { isReservedPropertyId, type PropertyDefinition, RESERVED_PROPERTY_ID } from '@shared/properties'
import type { SavedView } from '@shared/views'
import { nexusReorderIndex, type PaneRow, type PaneSlot, type Region } from './paneDndModel'

type VisibilityPatch = Pick<SavedView, 'property_order' | 'hidden_properties'>

/** The contexts section — always all three tiers, in the FIXED Areas · Topics · Projects order
 *  (never the view's column order; the rows stay put and only their hidden flag changes). */
export const CONTEXT_TIERS = [
  RESERVED_PROPERTY_ID.tier1,
  RESERVED_PROPERTY_ID.tier2,
  RESERVED_PROPERTY_ID.tier3
]
const CONTEXT_SET = new Set<string>(CONTEXT_TIERS)

/** The shown PROPERTIES section: the view's resolved column order minus Title and the tiers —
 *  schema props plus Modified when explicitly placed. */
export function shownPropertyIds(resolvedIds: string[]): string[] {
  return resolvedIds.filter((id) => id !== RESERVED_PROPERTY_ID.title && !CONTEXT_SET.has(id))
}

/** The hidden group's display order: schema props in COLLECTION order (never the view's), then
 *  Modified. Contexts never appear here (they ghost in place), and a stale hidden id displays
 *  nowhere but stays in the array (writes only ever filter the toggled id, so foreign keys
 *  survive — the loose-sidecar contract). */
export function hiddenListIds(hidden: string[], schema: PropertyDefinition[]): string[] {
  const set = new Set(hidden)
  return [
    ...schema.filter((d) => set.has(d.id) && !isReservedPropertyId(d.id)).map((d) => d.id),
    ...(set.has(RESERVED_PROPERTY_ID.modifiedAt) ? [RESERVED_PROPERTY_ID.modifiedAt] : [])
  ]
}

/** Place `id` at the properties section's without-dragged slot `toIndex` — the ONE write both
 *  drops share: a shown row's reorder and a hidden row's drag-in unhide are the same operation
 *  (the hidden filter is a no-op for an already-shown id). The section is a WINDOW into the full
 *  column order (Title + tiers live there too), so the slot translates through the successor
 *  anchor (the nexusReorderIndex idiom) before splicing; the full visible order is then written
 *  verbatim with every unlisted property_order id trailing, preserved (the columnReorder idiom). */
export function placeInShown(
  view: SavedView,
  fullVisibleIds: string[],
  sectionIds: string[],
  id: string,
  toIndex: number
): VisibilityPatch {
  const next = fullVisibleIds.filter((x) => x !== id)
  next.splice(nexusReorderIndex(fullVisibleIds, sectionIds, id, toIndex), 0, id)
  return {
    property_order: [...next, ...view.property_order.filter((x) => !next.includes(x))],
    hidden_properties: view.hidden_properties.filter((x) => x !== id)
  }
}

/** Hide a shown property — flag it, never move it: its property_order slot is its remembered
 *  spot, so a later unhide restores the property where it was instead of dumping it at the end. */
export function hideShown(view: SavedView, id: string): Pick<SavedView, 'hidden_properties'> {
  return {
    hidden_properties: view.hidden_properties.includes(id)
      ? view.hidden_properties
      : [...view.hidden_properties, id]
  }
}

/** Unhide via the eye — the flag lifts and the resolver re-emits the id at its remembered slot. */
export function unhide(view: SavedView, id: string): Pick<SavedView, 'hidden_properties'> {
  return { hidden_properties: view.hidden_properties.filter((x) => x !== id) }
}

/** The pane's slot rule (injected into PaneDnd in place of the Properties paneSlot). The shown
 *  zone ('assigned') takes positional drops — a shown row reorders, a hidden row unhides at the
 *  slot ('assign'; one handler, placeInShown), both with a drop line. The hidden zone ('all')
 *  takes a MEMBERSHIP drop from a shown row — hide ('unassign': no slot, the hidden order is
 *  derived), shown as the area highlight; a hidden row over its own zone stays inert (no reorder
 *  within hidden). The contexts block above both is dead space: null, release is a no-op. */
export function hiddenPaneSlot(
  rows: MeasuredRow[],
  byId: Map<string, PaneRow>,
  regions: { assigned: Region; all: Region },
  pointerY: number,
  draggedId: string
): PaneSlot | null {
  const dragged = byId.get(draggedId)
  if (!dragged) return null
  const within = (r: Region): boolean => pointerY >= r.top && pointerY <= r.bottom
  if (within(regions.all) && !within(regions.assigned)) {
    if (dragged.group !== 'assigned') return null
    return { drop: { kind: 'unassign', propId: draggedId }, lineY: null, highlightAll: true }
  }
  if (!within(regions.assigned)) return null
  const groupRows = rows.filter((r) => byId.get(r.id)?.group === 'assigned' && r.id !== draggedId)
  let i = 0
  while (i < groupRows.length && pointerY >= groupRows[i].mid) i++
  const last = groupRows[groupRows.length - 1]
  const lineY = i < groupRows.length ? groupRows[i].top : last ? last.bottom : regions.assigned.top
  return {
    drop: { kind: dragged.group === 'assigned' ? 'reorder-assigned' : 'assign', propId: draggedId, toIndex: i },
    lineY,
    highlightAll: false
  }
}
