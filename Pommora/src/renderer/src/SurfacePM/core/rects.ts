// Geometry resolution: the tree → per-tile pixel rects + row-divider hit zones.
// Pure math off the layout; the component layer renders from this and hands
// pointer deltas back to ops with the extents measured here. Heights are
// content-driven (nodeHeight); a row's shorter children end ragged — legal.

import type { DividerRef, LayoutNode, SurfaceLayout } from './model'
import { nodeHeight } from './model'

export interface Rect {
  x: number
  y: number
  w: number
  h: number
}

export interface DividerRect extends Rect {
  ref: DividerRef
  /** The row's usable width — resizeDivider's `extentPx`. */
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

export function computeGeometry(layout: SurfaceLayout, width: number, gap = 0): SurfaceGeometry {
  const tiles = new Map<string, Rect>()
  const dividers: DividerRect[] = []
  const bandEdges: BandEdgeRect[] = []

  const walk = (node: LayoutNode, x: number, y: number, w: number, band: number, path: number[]): void => {
    if (node.kind === 'tile') {
      tiles.set(node.id, { x, y, w, h: node.h })
      return
    }
    if (node.kind === 'column') {
      let cy = y
      node.children.forEach((child, i) => {
        walk(child, x, cy, w, band, [...path, i])
        cy += nodeHeight(child, gap) + gap
      })
      return
    }
    const gaps = gap * (node.children.length - 1)
    const usable = Math.max(0, w - gaps)
    const rowH = nodeHeight(node, gap)
    let cx = x
    node.children.forEach((child, i) => {
      const share = (node.ratios[i] ?? 0) * usable
      walk(child, cx, y, share, band, [...path, i])
      cx += share
      if (i < node.children.length - 1) {
        dividers.push({
          ref: { band, path, index: i },
          extentPx: usable,
          x: cx,
          y,
          w: gap,
          h: rowH
        })
        cx += gap
      }
    })
  }

  let y = 0
  layout.bands.forEach((band, i) => {
    walk(band.node, 0, y, width, i, [])
    y += nodeHeight(band.node, gap)
    // The seam CENTERLINE of the gap below this band — hit-testing's anchor.
    bandEdges.push({ band: i, x: 0, y: y + gap / 2, w: width, h: Math.max(gap, 1) })
    y += gap
  })

  return { tiles, dividers, bandEdges, totalHeight: Math.max(0, y - gap) }
}
