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

const dedupe = (values: number[]): number[] => [...new Set(values.map((v) => Math.round(v)))]

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
