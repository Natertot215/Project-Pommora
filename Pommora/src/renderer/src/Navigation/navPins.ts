// Pure pin-list reducers — no store, no IPC (unit-tested without a DOM). Pins are durable + ordered
// by a numeric fractional `order`; membership is keyed by navKey. The in-memory list is the sorted
// projection of the per-pin files; these helpers compute the single file each mutation rewrites.

import type { NavTarget, PinEntry } from '@shared/types'
import { navKey } from './navRecents'
import { keyBetween } from './order'

/** Sort pins deterministically: by fractional order, then navKey so a concurrent equal-order insert
 *  still orders the same on every machine. */
export function byOrder(a: PinEntry, b: PinEntry): number {
  return a.order - b.order || navKey(a).localeCompare(navKey(b))
}

/** Strip a pin down to its clean nav target (drops `order`/`deleted`) — for select-on-click + the
 *  tombstone remove call. */
export function cleanPinTarget(pin: PinEntry): NavTarget {
  const { order: _order, deleted: _deleted, ...target } = pin
  return target as NavTarget
}

/** A new pin for `target`, appended after the current last (order above the max). */
export function pinFor(target: NavTarget, pins: PinEntry[]): PinEntry {
  const max = pins.length ? Math.max(...pins.map((p) => p.order)) : null
  return { ...target, order: keyBetween(max, null) } as PinEntry
}

/** The moved pin with a recomputed fractional order for its new slot (active dropped onto over's
 *  position, mirroring the shared reorder helper's splice), or null on a no-op. */
export function reorderTo(pins: PinEntry[], activeKey: string, overKey: string): PinEntry | null {
  const sorted = [...pins].sort(byOrder)
  const from = sorted.findIndex((p) => navKey(p) === activeKey)
  const to = sorted.findIndex((p) => navKey(p) === overKey)
  if (from === -1 || to === -1 || from === to) return null
  const next = sorted.slice()
  next.splice(to, 0, next.splice(from, 1)[0])
  const idx = next.findIndex((p) => navKey(p) === activeKey)
  const before = next[idx - 1]?.order ?? null
  const after = next[idx + 1]?.order ?? null
  return { ...sorted[from], order: keyBetween(before, after) }
}
