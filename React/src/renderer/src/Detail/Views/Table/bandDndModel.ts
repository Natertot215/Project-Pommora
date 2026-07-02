// Pure model behind the table's band drag (group headers) — no React, no DOM. Hit-testing runs
// over the VISIBLE band list; order math runs over the FULL structural id set so collapsed
// subtrees survive every write. A drop slot resolves its IMPLIED PARENT from the band below the
// line — the router compares it against the dragged band's current parent to pick reorder vs
// reparent (a flat array alone can never lift a child past its parent).

import type { ResolvedGroup } from '@shared/types'
import { type MeasuredRow, nextOrder } from '@renderer/Sidebar/sidebarDndModel'

export interface Band {
  id: string
  kind: 'set' | 'property'
  depth: number
  parentId: string | null
}

export interface BandSlot {
  beforeId: string | null
  impliedParentId: string | null
  nestInto: string | null
  lineY: number
}

/** Top/bottom fraction of a set band that reads as a before/after slot; the middle nests. */
const NEST_ZONE = 0.3

/** The visible band headers in display order — the live `collapsed` set prunes hidden subtrees
 *  (a ResolvedGroup's own isCollapsed is a snapshot; the render reads live state). The ungrouped
 *  tail is a non-entity: no band, no drag, no target. */
export function flattenBands(groups: ResolvedGroup[], collapsed: Set<string>): Band[] {
  const out: Band[] = []
  const walk = (gs: ResolvedGroup[], depth: number, parentId: string | null): void => {
    for (const g of gs) {
      if (g.kind === 'ungrouped') continue
      out.push({ id: g.key, kind: g.kind === 'structural-set' ? 'set' : 'property', depth, parentId })
      if (g.children && !collapsed.has(g.key)) walk(g.children, depth + 1, g.key)
    }
  }
  walk(groups, 0, null)
  return out
}

/** Every structural set id in tree order, collapsed subtrees INCLUDED — the id universe order
 *  writes must merge against so hidden siblings survive. Never contains the ungrouped key. */
export function allStructuralIds(groups: ResolvedGroup[]): string[] {
  const out: string[] = []
  const walk = (gs: ResolvedGroup[]): void => {
    for (const g of gs) {
      if (g.kind !== 'structural-set') continue
      out.push(g.key)
      if (g.children) walk(g.children)
    }
  }
  walk(groups)
  return out
}

/** True when `targetId` is a set band outside the dragged band's subtree — the cycle guard for
 *  nest-into (walks parent links up from the target, the sidebar's isSelfOrDescendant shape). */
export function canNest(draggedId: string, targetId: string, bands: Band[]): boolean {
  const byId = new Map(bands.map((b) => [b.id, b]))
  if (byId.get(targetId)?.kind !== 'set') return false
  let cur: string | null = targetId
  while (cur) {
    if (cur === draggedId) return false
    cur = byId.get(cur)?.parentId ?? null
  }
  return true
}

/** Resolve the pointer's drop slot against the frozen band snapshot. Headers are NOT adjacent in
 *  the real render — a band OWNS its whole region, header top to the next header's top (its data
 *  rows included), so hovering deep inside a group can never hand the slot to the next header. A
 *  set band nests from its header middle AND its row region (the sidebar's hover-a-container's-
 *  content precedent), cycle-guarded with a fall-through; before/after slots imply the parent of
 *  the band below the line, skipping the dragged subtree so a slot can never land inside it.
 *  Below the last header's own rows stays the root append — the drag-to-end escape hatch.
 *  Null = no legal slot. */
export function bandSlot(
  bands: Band[],
  measured: MeasuredRow[],
  y: number,
  draggedId: string
): BandSlot | null {
  const byId = new Map(bands.map((b) => [b.id, b]))
  const rows = measured.filter((m) => byId.has(m.id))
  if (rows.length === 0) return null

  const inDraggedSubtree = (id: string): boolean => {
    let cur: string | null = id
    while (cur) {
      if (cur === draggedId) return true
      cur = byId.get(cur)?.parentId ?? null
    }
    return false
  }

  // The slot before rows[i]: the band below the line owns the level. Skipping the dragged
  // subtree makes "just above the dragged band" resolve to its own current position (a no-op)
  // instead of an inside-itself slot.
  const slotBefore = (i: number, lineY: number): BandSlot | null => {
    let j = i
    while (j < rows.length && inDraggedSubtree(rows[j].id)) j++
    if (j >= rows.length) return { beforeId: null, impliedParentId: null, nestInto: null, lineY }
    const below = byId.get(rows[j].id)
    if (!below) return null
    if (below.parentId !== null && inDraggedSubtree(below.parentId)) return null
    return { beforeId: below.id, impliedParentId: below.parentId, nestInto: null, lineY }
  }

  // Hovered band by REGION — the last header whose top sits at/above the pointer.
  let idx = -1
  for (const [i, m] of rows.entries()) {
    if (y >= m.top) idx = i
    else break
  }
  if (idx === -1) return slotBefore(0, rows[0].top)
  const row = rows[idx]
  const band = byId.get(row.id)
  if (!band) return null
  const inset = (row.bottom - row.top) * NEST_ZONE

  if (y < row.top + inset) return slotBefore(idx, row.top)
  if (idx === rows.length - 1 && y >= row.bottom) {
    return { beforeId: null, impliedParentId: null, nestInto: null, lineY: row.bottom }
  }
  const inNestSpan = y >= row.bottom || y < row.bottom - inset
  if (band.kind === 'set' && inNestSpan && canNest(draggedId, band.id, bands)) {
    return { beforeId: null, impliedParentId: band.id, nestInto: band.id, lineY: row.mid }
  }
  if (y < row.mid) return slotBefore(idx, row.top)
  return slotBefore(idx + 1, rows[idx + 1] ? rows[idx + 1].top : row.bottom)
}

/** The view's structural band order after a reorder drop — merge-then-move: keep the prior
 *  order's surviving ids, append tree ids it never listed (tree order), then move the dragged id
 *  before `beforeId` (null = append). Collapsed siblings always survive: the merge runs over the
 *  FULL id set, never the visible flatten. */
export function structuralOrderAfterDrop(
  priorOrder: string[],
  fullTreeIds: string[],
  draggedId: string,
  beforeId: string | null
): string[] {
  const tree = new Set(fullTreeIds)
  const kept = priorOrder.filter((id) => tree.has(id))
  const listed = new Set(kept)
  const seeded = [...kept, ...fullTreeIds.filter((id) => !listed.has(id))]
  return nextOrder(seeded, draggedId, beforeId)
}

/** The property band order after a drop, over the present bucket keys. */
export function propertyOrderAfterDrop(
  presentKeys: string[],
  draggedKey: string,
  beforeKey: string | null
): string[] {
  return nextOrder(presentKeys, draggedKey, beforeKey)
}

/** The destination's fs `set_order` for a reparent commit: its CURRENT children + the moved id
 *  APPENDED — never the visual drop position, which persists only in the view's group_order
 *  (C-4: the per-view order must not leak into the filesystem). */
export function reparentFsOrder(destChildIds: string[], movedId: string): string[] {
  return [...destChildIds.filter((id) => id !== movedId), movedId]
}
