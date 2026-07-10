// Edge → boundary resolution: blocks resize by their own edges and corners
// (window-style), never by bars in the gaps. Dragging a tile's edge moves the
// shared boundary it sits on — the divider of the nearest ancestor split running
// that direction, or the band's bottom edge when no inner boundary exists.

import type { DividerRef, Edge, SurfaceLayout } from './model'
import { findTile } from './model'

export type EdgeBoundary =
  | { kind: 'divider'; ref: DividerRef }
  | { kind: 'band'; band: number }
  | null

export function resolveEdge(layout: SurfaceLayout, tileId: string, edge: Edge): EdgeBoundary {
  const at = findTile(layout, tileId)
  if (!at) return null

  const dir = edge === 'e' || edge === 'w' ? 'row' : 'column'
  const trailing = edge === 'e' || edge === 's'

  for (let depth = at.path.length - 1; depth >= 0; depth--) {
    const parentPath = at.path.slice(0, depth)
    let node = layout.bands[at.band]?.node
    for (const i of parentPath) {
      if (node?.kind !== 'split') return null
      node = node.children[i]
    }
    if (node?.kind !== 'split' || node.dir !== dir) continue

    const childIndex = at.path[depth] as number
    if (trailing && childIndex < node.children.length - 1)
      return { kind: 'divider', ref: { band: at.band, path: parentPath, index: childIndex } }
    if (!trailing && childIndex > 0)
      return { kind: 'divider', ref: { band: at.band, path: parentPath, index: childIndex - 1 } }
  }

  // No inner boundary: the band's bottom edge is the page-flow resize; the
  // other outer edges are the surface's own bounds and don't resize.
  if (edge === 's') return { kind: 'band', band: at.band }
  return null
}
