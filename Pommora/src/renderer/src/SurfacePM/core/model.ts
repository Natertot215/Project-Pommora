// SurfacePM layout model — a tessellated mosaic as a split tree.
// The page is a vertical stack of bands (absolute heights, so the page flows);
// inside a band, nested row/column splits divide the space by ratios with tiles
// as leaves. Holes are impossible by construction: every region is covered by
// exactly one leaf, deletion collapses splits, insertion splits a region.

export type SplitDir = 'row' | 'column'

export interface SplitNode {
  kind: 'split'
  dir: SplitDir
  ratios: number[]
  children: LayoutNode[]
}

export interface TileLeaf {
  kind: 'tile'
  id: string
}

export type LayoutNode = SplitNode | TileLeaf

export interface Band {
  height: number
  node: LayoutNode
}

export interface SurfaceLayout {
  bands: Band[]
}

/** Which edge of a target region a drop lands on — determines split direction + order. */
export type Edge = 'n' | 's' | 'e' | 'w'

/** Address of a node inside a band: child indices from the band root. */
export interface NodePath {
  band: number
  path: number[]
}

/** The divider between children[index] and children[index+1] of the split at `path`. */
export interface DividerRef extends NodePath {
  index: number
}

export const emptyLayout = (): SurfaceLayout => ({ bands: [] })

export function nodeAt(layout: SurfaceLayout, ref: NodePath): LayoutNode | undefined {
  let node = layout.bands[ref.band]?.node
  for (const i of ref.path) {
    if (node?.kind !== 'split') return undefined
    node = node.children[i]
  }
  return node
}

export function findTile(
  layout: SurfaceLayout,
  tileId: string
): { band: number; path: number[] } | undefined {
  const walk = (node: LayoutNode, path: number[]): number[] | undefined => {
    if (node.kind === 'tile') return node.id === tileId ? path : undefined
    for (let i = 0; i < node.children.length; i++) {
      const child = node.children[i]
      if (!child) continue
      const hit = walk(child, [...path, i])
      if (hit) return hit
    }
    return undefined
  }
  for (let b = 0; b < layout.bands.length; b++) {
    const band = layout.bands[b]
    if (!band) continue
    const hit = walk(band.node, [])
    if (hit) return { band: b, path: hit }
  }
  return undefined
}

export function tileIds(layout: SurfaceLayout): string[] {
  const out: string[] = []
  const walk = (node: LayoutNode): void => {
    if (node.kind === 'tile') {
      out.push(node.id)
      return
    }
    for (const child of node.children) walk(child)
  }
  for (const band of layout.bands) walk(band.node)
  return out
}

export function cloneNode(node: LayoutNode): LayoutNode {
  if (node.kind === 'tile') return { kind: 'tile', id: node.id }
  return {
    kind: 'split',
    dir: node.dir,
    ratios: [...node.ratios],
    children: node.children.map(cloneNode)
  }
}

export function cloneLayout(layout: SurfaceLayout): SurfaceLayout {
  return { bands: layout.bands.map((b) => ({ height: b.height, node: cloneNode(b.node) })) }
}

/** A structurally valid tree: splits hold 2+ children with matching, positive ratios. */
export function validateLayout(layout: SurfaceLayout): string[] {
  const problems: string[] = []
  const walk = (node: LayoutNode, where: string): void => {
    if (node.kind === 'tile') return
    if (node.children.length < 2) problems.push(`${where}: split with ${node.children.length} child`)
    if (node.ratios.length !== node.children.length)
      problems.push(`${where}: ${node.ratios.length} ratios for ${node.children.length} children`)
    if (node.ratios.some((r) => !(r > 0))) problems.push(`${where}: non-positive ratio`)
    const sum = node.ratios.reduce((a, r) => a + r, 0)
    if (Math.abs(sum - 1) > 1e-6) problems.push(`${where}: ratios sum to ${sum}`)
    node.children.forEach((child, i) => walk(child, `${where}.${i}`))
  }
  layout.bands.forEach((band, i) => {
    if (!(band.height > 0)) problems.push(`band ${i}: non-positive height`)
    walk(band.node, `band ${i}`)
  })
  const ids = tileIds(layout)
  if (new Set(ids).size !== ids.length) problems.push('duplicate tile id')
  return problems
}
