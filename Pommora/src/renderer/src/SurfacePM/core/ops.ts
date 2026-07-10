// The tessellation-preserving operations. Every op returns a new layout; the
// input is never mutated. The invariant each op maintains: splits hold 2+
// children, ratios sum to 1, no region is ever left uncovered.

import type { Band, DividerRef, Edge, LayoutNode, SplitNode, SurfaceLayout } from './model'
import { cloneLayout, findTile } from './model'

const dirOf = (edge: Edge): 'row' | 'column' => (edge === 'e' || edge === 'w' ? 'row' : 'column')
const newFirst = (edge: Edge): boolean => edge === 'w' || edge === 'n'

function renormalize(ratios: number[]): number[] {
  const sum = ratios.reduce((a, r) => a + r, 0)
  return ratios.map((r) => r / sum)
}

function replaceAt(node: LayoutNode, path: number[], next: LayoutNode): LayoutNode {
  if (path.length === 0) return next
  if (node.kind !== 'split') return node
  const [head, ...rest] = path
  const children = node.children.map((child, i) =>
    i === head ? replaceAt(child, rest, next) : child
  )
  return { ...node, children }
}

/** Split the target tile's region on `edge`, the new tile taking `share` of it.
 *  When the target's parent already splits in the same direction, the new tile
 *  splices in as a sibling (taking `share` of the target's ratio) instead of nesting. */
export function splitAtTile(
  layout: SurfaceLayout,
  targetId: string,
  edge: Edge,
  newId: string,
  share = 0.5
): SurfaceLayout {
  const at = findTile(layout, targetId)
  if (!at || findTile(layout, newId)) return layout

  const next = cloneLayout(layout)
  const band = next.bands[at.band]
  if (!band) return layout
  const dir = dirOf(edge)
  const first = newFirst(edge)
  const newLeaf: LayoutNode = { kind: 'tile', id: newId }

  const parentPath = at.path.slice(0, -1)
  const childIndex = at.path[at.path.length - 1]
  const parent =
    at.path.length > 0
      ? (parentPath.reduce<LayoutNode>(
          (n, i) => (n.kind === 'split' ? (n.children[i] ?? n) : n),
          band.node
        ) as SplitNode)
      : null

  if (parent && parent.kind === 'split' && parent.dir === dir && childIndex !== undefined) {
    const targetRatio = parent.ratios[childIndex] ?? 0
    const insertAt = first ? childIndex : childIndex + 1
    parent.children.splice(insertAt, 0, newLeaf)
    parent.ratios[childIndex] = targetRatio * (1 - share)
    parent.ratios.splice(insertAt, 0, targetRatio * share)
    parent.ratios = renormalize(parent.ratios)
    return next
  }

  const target: LayoutNode = { kind: 'tile', id: targetId }
  const split: SplitNode = {
    kind: 'split',
    dir,
    ratios: first ? [share, 1 - share] : [1 - share, share],
    children: first ? [newLeaf, target] : [target, newLeaf]
  }
  band.node = replaceAt(band.node, at.path, split)
  return next
}

/** Remove a tile; its siblings absorb the space (ratios renormalize), a split
 *  left with one child collapses into it, a band left tileless disappears. */
export function removeTile(layout: SurfaceLayout, tileId: string): SurfaceLayout {
  const at = findTile(layout, tileId)
  if (!at) return layout

  const next = cloneLayout(layout)
  const band = next.bands[at.band]
  if (!band) return layout

  if (at.path.length === 0) {
    next.bands.splice(at.band, 1)
    return next
  }

  const parentPath = at.path.slice(0, -1)
  const childIndex = at.path[at.path.length - 1] as number
  const parent = parentPath.reduce<LayoutNode>(
    (n, i) => (n.kind === 'split' ? (n.children[i] ?? n) : n),
    band.node
  ) as SplitNode

  parent.children.splice(childIndex, 1)
  parent.ratios.splice(childIndex, 1)
  parent.ratios = renormalize(parent.ratios)

  if (parent.children.length === 1) {
    const survivor = parent.children[0] as LayoutNode
    band.node = replaceAt(band.node, parentPath, survivor)
  }
  return next
}

/** Move = remove + split at the new target. A drop on the tile itself no-ops. */
export function moveTile(
  layout: SurfaceLayout,
  tileId: string,
  targetId: string,
  edge: Edge
): SurfaceLayout {
  if (tileId === targetId) return layout
  if (!findTile(layout, tileId) || !findTile(layout, targetId)) return layout
  const removed = removeTile(layout, tileId)
  return splitAtTile(removed, targetId, edge, tileId)
}

/** Insert a tile as its own full-width band at `index`. */
export function insertBand(
  layout: SurfaceLayout,
  index: number,
  tileId: string,
  height: number
): SurfaceLayout {
  if (findTile(layout, tileId)) return layout
  const next = cloneLayout(layout)
  const at = Math.max(0, Math.min(index, next.bands.length))
  const band: Band = { height, node: { kind: 'tile', id: tileId } }
  next.bands.splice(at, 0, band)
  return next
}

/** Move an existing tile out into its own band at `index` (an index against the
 *  layout as given — when the tile currently IS a band above the target, its
 *  removal shifts the band list, so the insertion compensates). */
export function moveTileToBand(
  layout: SurfaceLayout,
  tileId: string,
  index: number,
  height: number
): SurfaceLayout {
  const at = findTile(layout, tileId)
  if (!at) return layout
  const ownBand = at.path.length === 0
  const insertAt = ownBand && at.band < index ? index - 1 : index
  if (ownBand && insertAt === at.band) return layout
  const removed = removeTile(layout, tileId)
  return insertBand(removed, insertAt, tileId, height)
}

/** Drag the divider between two children of a split: redistribute the pair's
 *  ratio by `deltaPx`, each side clamped to `minPx`. `extentPx` is the split's
 *  size along its direction (the component layer measures it). */
export function resizeDivider(
  layout: SurfaceLayout,
  ref: DividerRef,
  deltaPx: number,
  extentPx: number,
  minPx: number
): SurfaceLayout {
  if (extentPx <= 0) return layout
  const next = cloneLayout(layout)
  let node = next.bands[ref.band]?.node
  for (const i of ref.path) {
    if (node?.kind !== 'split') return layout
    node = node.children[i]
  }
  if (node?.kind !== 'split') return layout
  const a = node.ratios[ref.index]
  const b = node.ratios[ref.index + 1]
  if (a === undefined || b === undefined) return layout

  const pair = a + b
  const pairPx = pair * extentPx
  const minRatio = Math.min(minPx / extentPx, pair / 2)
  const nextA = clamp(a + deltaPx / extentPx, minRatio, pair - minRatio)
  if (pairPx < minPx * 2) return layout

  node.ratios[ref.index] = nextA
  node.ratios[ref.index + 1] = pair - nextA
  return next
}

/** Stretch a tile's height by `deltaPx` WITHOUT deforming its stacked neighbors:
 *  every column-split ancestor re-ratios so the tile's branch absorbs the whole
 *  delta while sibling branches keep their exact pixels, and the band grows by
 *  the same amount — the page flows, nothing redistributes. (Full-height row
 *  siblings still stretch with the band: holes can't exist.) */
export function stretchTileHeight(
  layout: SurfaceLayout,
  tileId: string,
  deltaPx: number,
  minPx: number,
  gap: number
): SurfaceLayout {
  if (deltaPx === 0) return layout
  const at = findTile(layout, tileId)
  if (!at) return layout
  const band = layout.bands[at.band]
  if (!band) return layout

  // First pass: the tile's current pixel height (band height filtered through
  // each column-split ancestor's ratio; row splits don't partition height).
  let heightPx = band.height
  const usables: number[] = []
  let node: LayoutNode = band.node
  for (const i of at.path) {
    if (node.kind !== 'split') return layout
    if (node.dir === 'column') {
      const usable = heightPx - gap * (node.children.length - 1)
      usables.push(usable)
      heightPx = (node.ratios[i] ?? 0) * usable
    }
    node = node.children[i] as LayoutNode
  }
  const delta = Math.max(minPx - heightPx, deltaPx)
  if (delta === 0) return layout

  // Second pass on the clone: each column ancestor's branch gains `delta` px,
  // its siblings keep theirs; the band absorbs the delta.
  const next = cloneLayout(layout)
  const nextBand = next.bands[at.band] as Band
  nextBand.height = band.height + delta
  let n: LayoutNode = nextBand.node
  let colIdx = 0
  for (const i of at.path) {
    if (n.kind !== 'split') break
    if (n.dir === 'column') {
      const usable = usables[colIdx++] as number
      const grown = usable + delta
      n.ratios = n.ratios.map((r, j) => {
        const px = r * usable
        return (j === i ? px + delta : px) / grown
      })
    }
    n = n.children[i] as LayoutNode
  }
  return next
}

/** Drag a band's bottom edge: the band grows or shrinks and the page flows. */
export function resizeBand(
  layout: SurfaceLayout,
  band: number,
  deltaPx: number,
  minPx: number
): SurfaceLayout {
  const target = layout.bands[band]
  if (!target) return layout
  const next = cloneLayout(layout)
  const nextBand = next.bands[band] as Band
  nextBand.height = Math.max(minPx, target.height + deltaPx)
  return next
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, n))
}
