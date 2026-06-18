import type { Box } from './shared'

// Keyboard-drag direction model. Geometric and strategy-agnostic, like the pointer collision: from
// the current slot, an arrow picks the nearest slot that lies AHEAD in that direction, biased toward
// alignment on the perpendicular axis so a grid steps to the cell directly above/below/beside.

export type Dir = { x: number; y: number }

export const ARROW_DIRS: Record<string, Dir> = {
  ArrowUp: { x: 0, y: -1 },
  ArrowDown: { x: 0, y: 1 },
  ArrowLeft: { x: -1, y: 0 },
  ArrowRight: { x: 1, y: 0 }
}

/** Next slot index from `over` in arrow direction `dir`. Returns `over` if nothing lies ahead. */
export function keyboardNext(rects: Box[], over: number, dir: Dir): number {
  const c = rects[over]
  if (!c) return over
  let best = over
  let bestCost = Infinity
  rects.forEach((r, i) => {
    if (i === over) return
    const dx = r.cx - c.cx
    const dy = r.cy - c.cy
    const along = dx * dir.x + dy * dir.y
    if (along <= 0) return // not ahead in the arrow direction
    const perp = Math.abs(dx * dir.y - dy * dir.x)
    const cost = along + perp * 2 // bias toward aligned neighbours (grid rows/columns)
    if (cost < bestCost) {
      bestCost = cost
      best = i
    }
  })
  return best
}
