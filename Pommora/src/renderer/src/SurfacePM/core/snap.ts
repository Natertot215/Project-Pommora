// Alignment snapping: a dragged boundary magnetizes to other blocks' edges when
// it comes within `threshold` px of perfect alignment — the tiny form-lock that
// makes near-aligned layouts land exactly aligned.

import type { SurfaceGeometry } from './rects'

export function snapAxis(value: number, candidates: number[], threshold: number): number {
  let best = value
  let bestDistance = threshold + 1
  for (const c of candidates) {
    const d = Math.abs(c - value)
    if (d < bestDistance || (d === bestDistance && c > best)) {
      best = c
      bestDistance = d
    }
  }
  return bestDistance <= threshold ? best : value
}

// Dedupe by rounded key but keep RAW positions — a snap must land exactly on the
// neighbor's edge, and a rounded candidate vs a fractional boundary would commit
// noise-level deltas on every near-aligned drag.
const dedupe = (values: number[]): number[] => {
  const seen = new Set<number>()
  const out: number[] = []
  for (const v of values) {
    const key = Math.round(v)
    if (!seen.has(key)) {
      seen.add(key)
      out.push(v)
    }
  }
  return out
}

/** Every tile's left + right edge — the vertical-boundary magnet lines. */
export function xCandidates(geometry: SurfaceGeometry): number[] {
  const out: number[] = []
  for (const r of geometry.tiles.values()) out.push(r.x, r.x + r.w)
  return dedupe(out)
}

/** Every tile's top + bottom edge — the horizontal-boundary magnet lines. */
export function yCandidates(geometry: SurfaceGeometry): number[] {
  const out: number[] = []
  for (const r of geometry.tiles.values()) out.push(r.y, r.y + r.h)
  return dedupe(out)
}
