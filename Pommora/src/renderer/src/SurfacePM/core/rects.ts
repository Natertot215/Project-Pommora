// Geometry resolution: the tree → per-tile pixel rects + divider hit zones.
// Pure math off the layout; the component layer renders from this and hands
// pointer deltas back to ops with the extents measured here.

import type { DividerRef, LayoutNode, SurfaceLayout } from './model'

export interface Rect {
  x: number
  y: number
  w: number
  h: number
}

export interface DividerRect extends Rect {
  ref: DividerRef
  dir: 'row' | 'column'
  /** The split's pixel extent along its direction — resizeDivider's `extentPx`. */
  extentPx: number
}

export interface BandEdgeRect extends Rect {
  band: number
}

export interface SurfaceGeometry {
  tiles: Map<string, Rect>
  dividers: DividerRect[]
  bandEdges: BandEdgeRect[]
  totalHeight: number
}

export function computeGeometry(
  layout: SurfaceLayout,
  width: number,
  gap = 0
): SurfaceGeometry {
  const tiles = new Map<string, Rect>()
  const dividers: DividerRect[] = []
  const bandEdges: BandEdgeRect[] = []

  const walk = (node: LayoutNode, rect: Rect, band: number, path: number[]): void => {
    if (node.kind === 'tile') {
      tiles.set(node.id, rect)
      return
    }
    const horizontal = node.dir === 'row'
    const extent = horizontal ? rect.w : rect.h
    const gaps = gap * (node.children.length - 1)
    const usable = Math.max(0, extent - gaps)
    let cursor = horizontal ? rect.x : rect.y

    node.children.forEach((child, i) => {
      const share = (node.ratios[i] ?? 0) * usable
      const childRect: Rect = horizontal
        ? { x: cursor, y: rect.y, w: share, h: rect.h }
        : { x: rect.x, y: cursor, w: rect.w, h: share }
      walk(child, childRect, band, [...path, i])
      cursor += share

      if (i < node.children.length - 1) {
        dividers.push({
          ref: { band, path, index: i },
          dir: node.dir,
          extentPx: usable,
          x: horizontal ? cursor : rect.x,
          y: horizontal ? rect.y : cursor,
          w: horizontal ? gap : rect.w,
          h: horizontal ? rect.h : gap
        })
        cursor += gap
      }
    })
  }

  let y = 0
  layout.bands.forEach((band, i) => {
    walk(band.node, { x: 0, y, w: width, h: band.height }, i, [])
    y += band.height
    bandEdges.push({ band: i, x: 0, y: y - gap / 2, w: width, h: Math.max(gap, 1) })
    y += gap
  })

  return { tiles, dividers, bandEdges, totalHeight: Math.max(0, y - gap) }
}
