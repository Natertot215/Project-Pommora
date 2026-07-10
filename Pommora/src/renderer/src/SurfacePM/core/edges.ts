// Edge → boundary resolution: blocks resize by their own edges and corners
// (window-style, never bars in the gaps). East/west edges move the nearest
// ancestor ROW divider (width splitter). A north edge negotiates with the
// stacked neighbor directly above (the nearest COLUMN ancestor where this
// branch isn't first). South edges never resolve here — they stretch the tile
// itself (the caller goes straight to stretchTileHeight).

import type { DividerRef, Edge, SurfaceLayout } from './model'
import { findTile } from './model'

export type EdgeBoundary =
  | { kind: 'divider'; ref: DividerRef }
  | { kind: 'stack'; ref: DividerRef }
  | null

export function resolveEdge(layout: SurfaceLayout, tileId: string, edge: Edge): EdgeBoundary {
  if (edge === 's') return null
  const at = findTile(layout, tileId)
  if (!at) return null

  const wantKind = edge === 'n' ? 'column' : 'row'
  const trailing = edge === 'e'

  for (let depth = at.path.length - 1; depth >= 0; depth--) {
    const parentPath = at.path.slice(0, depth)
    let node = layout.bands[at.band]?.node
    for (const i of parentPath) {
      if (!node || node.kind === 'tile') return null
      node = node.children[i]
    }
    if (!node || node.kind !== wantKind) continue

    const childIndex = at.path[depth] as number
    if (edge === 'n') {
      if (childIndex > 0)
        return { kind: 'stack', ref: { band: at.band, path: parentPath, index: childIndex - 1 } }
      continue
    }
    if (trailing && childIndex < node.children.length - 1)
      return { kind: 'divider', ref: { band: at.band, path: parentPath, index: childIndex } }
    if (!trailing && childIndex > 0)
      return { kind: 'divider', ref: { band: at.band, path: parentPath, index: childIndex - 1 } }
  }
  return null
}
