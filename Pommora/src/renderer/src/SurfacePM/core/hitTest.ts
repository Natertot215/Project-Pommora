// Drop-target resolution for tile moves: a pointer position resolves to a band
// insertion (above the first band, on a between-band seam, or past the bottom)
// or the hovered tile's nearest edge — never the dragged tile itself. Band zones
// win over the tiles they straddle; `bandZonePx` is the live-tuning knob.

import type { Edge, SurfaceLayout } from './model'
import type { SurfaceGeometry } from './rects'

export type DropTarget =
  | { kind: 'tile'; id: string; edge: Edge }
  | { kind: 'band'; index: number }
  | null

export function hitTest(
  geometry: SurfaceGeometry,
  layout: SurfaceLayout,
  dragId: string,
  px: number,
  py: number,
  bandZonePx = 10
): DropTarget {
  if (py < bandZonePx) return { kind: 'band', index: 0 }
  if (py > geometry.totalHeight - bandZonePx) return { kind: 'band', index: layout.bands.length }
  for (const seam of geometry.bandEdges.slice(0, -1)) {
    if (Math.abs(py - seam.y) <= bandZonePx) return { kind: 'band', index: seam.band + 1 }
  }

  for (const [id, r] of geometry.tiles) {
    if (id === dragId) continue
    if (px < r.x || px > r.x + r.w || py < r.y || py > r.y + r.h) continue
    const relX = (px - r.x) / r.w
    const relY = (py - r.y) / r.h
    const dists: Array<[Edge, number]> = [
      ['w', relX],
      ['e', 1 - relX],
      ['n', relY],
      ['s', 1 - relY]
    ]
    dists.sort((a, b) => a[1] - b[1])
    return { kind: 'tile', id, edge: dists[0]?.[0] ?? 'e' }
  }
  return null
}
