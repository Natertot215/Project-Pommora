import { describe, expect, it } from 'vitest'
import type { ColumnNode, RowNode, SurfaceLayout, TileLeaf } from './model'
import { findTile, getTile, nodeHeight, tileIds, validateLayout } from './model'
import {
  insertBand,
  moveTile,
  moveTileToBand,
  removeTile,
  resizeBandPair,
  resizeDivider,
  resizeStackPair,
  splitAtTile,
  stretchTileHeight,
} from './ops'
import { computeGeometry } from './rects'

const single = (): SurfaceLayout => insertBand({ bands: [] }, 0, 'a', 200)

const assertValid = (layout: SurfaceLayout): void => {
  expect(validateLayout(layout)).toEqual([])
}

describe('insertBand', () => {
  it('creates a full-width band and rejects duplicate ids', () => {
    const l1 = single()
    assertValid(l1)
    expect(tileIds(l1)).toEqual(['a'])
    expect(getTile(l1, 'a')?.h).toBe(200)
    expect(insertBand(l1, 0, 'a', 100)).toBe(l1)
  })

  it('clamps the index', () => {
    const l = insertBand(single(), 99, 'b', 100)
    expect((l.bands[1]?.node as TileLeaf).id).toBe('b')
  })
})

describe('splitAtTile', () => {
  it('splits east into a row: widths share, heights stay', () => {
    const l = splitAtTile(single(), 'a', 'e', 'b')
    assertValid(l)
    const node = l.bands[0]?.node as RowNode
    expect(node.kind).toBe('row')
    expect(node.children.map((c) => (c as TileLeaf).id)).toEqual(['a', 'b'])
    expect((node.children[1] as TileLeaf).h).toBe(200)
  })

  it('splits south into a column: the target height divides between the two', () => {
    const l = splitAtTile(single(), 'a', 's', 'b')
    assertValid(l)
    const node = l.bands[0]?.node as ColumnNode
    expect(node.kind).toBe('column')
    expect((node.children[0] as TileLeaf).h).toBe(100)
    expect((node.children[1] as TileLeaf).h).toBe(100)
  })

  it('splices as a sibling when the parent runs the same way', () => {
    const l = splitAtTile(splitAtTile(single(), 'a', 'e', 'b'), 'b', 'e', 'c')
    assertValid(l)
    const node = l.bands[0]?.node as RowNode
    expect(node.children.map((c) => (c as TileLeaf).id)).toEqual(['a', 'b', 'c'])
    expect(node.ratios[0]).toBeCloseTo(0.5)
    expect(node.ratios[1]).toBeCloseTo(0.25)
    expect(node.ratios[2]).toBeCloseTo(0.25)
  })

  it('column splices stack without touching sibling heights', () => {
    const l = splitAtTile(splitAtTile(single(), 'a', 's', 'b'), 'b', 's', 'c')
    assertValid(l)
    const node = l.bands[0]?.node as ColumnNode
    expect(node.children.map((c) => (c as TileLeaf).id)).toEqual(['a', 'b', 'c'])
    expect((node.children[0] as TileLeaf).h).toBe(100)
    expect((node.children[1] as TileLeaf).h).toBe(50)
    expect((node.children[2] as TileLeaf).h).toBe(50)
  })

  it('rejects unknown targets and duplicate ids', () => {
    const l = single()
    expect(splitAtTile(l, 'ghost', 'e', 'b')).toBe(l)
    expect(splitAtTile(l, 'a', 'e', 'a')).toBe(l)
  })
})

describe('removeTile', () => {
  it('lets row siblings absorb the width and collapses the split', () => {
    const l = removeTile(splitAtTile(single(), 'a', 'e', 'b'), 'b')
    assertValid(l)
    expect((l.bands[0]?.node as TileLeaf).id).toBe('a')
  })

  it('closes a column stack without touching sibling heights', () => {
    const three = splitAtTile(splitAtTile(single(), 'a', 's', 'b'), 'b', 's', 'c')
    const l = removeTile(three, 'b')
    assertValid(l)
    const node = l.bands[0]?.node as ColumnNode
    expect((node.children[0] as TileLeaf).h).toBe(100)
    expect((node.children[1] as TileLeaf).h).toBe(50)
  })

  it('drops a band whose only tile is removed', () => {
    const l = removeTile(insertBand(single(), 1, 'b', 100), 'b')
    assertValid(l)
    expect(l.bands).toHaveLength(1)
  })
})

describe('moveTile', () => {
  it('relocates across the tree, preserving the mover height', () => {
    const three = splitAtTile(splitAtTile(single(), 'a', 'e', 'b'), 'b', 's', 'c')
    const l = moveTile(three, 'c', 'a', 'n')
    assertValid(l)
    expect(tileIds(l).sort()).toEqual(['a', 'b', 'c'])
    expect(getTile(l, 'c')?.h).toBe(getTile(three, 'c')?.h)
    expect(findTile(l, 'c')?.path[0]).toBeDefined()
  })

  it('band pair: the seam negotiates, blocks below stay put', () => {
    let l = insertBand(single(), 1, 'b', 160)
    l = insertBand(l, 2, 'c', 120)
    const r = resizeBandPair(l, 0, -30, 64)
    expect(getTile(r, 'a')?.h).toBe(170)
    expect(getTile(r, 'b')?.h).toBe(190)
    expect(getTile(r, 'c')?.h).toBe(120)
    // clamps at min; declines when a side is a split
    expect(getTile(resizeBandPair(l, 0, -150, 64), 'a')?.h).toBe(64)
    const split = splitAtTile(l, 'a', 'e', 'x')
    expect(resizeBandPair(split, 0, -10, 64)).toBe(split)
  })

  it('adopts the target height on a row placement — the drop lands flush', () => {
    let l = insertBand(single(), 1, 'b', 240)
    l = moveTile(l, 'b', 'a', 'e')
    assertValid(l)
    expect(getTile(l, 'b')?.h).toBe(getTile(l, 'a')?.h)
  })

  it('no-ops on self-drop and unknown ids', () => {
    const l = splitAtTile(single(), 'a', 'e', 'b')
    expect(moveTile(l, 'a', 'a', 'e')).toBe(l)
    expect(moveTile(l, 'ghost', 'a', 'e')).toBe(l)
  })

  it('moves a tile out into its own band, keeping its height', () => {
    const l = moveTileToBand(splitAtTile(single(), 'a', 's', 'b'), 'b', 1)
    assertValid(l)
    expect(l.bands).toHaveLength(2)
    expect((l.bands[1]?.node as TileLeaf).h).toBe(100)
  })

  it('reorders whole bands in both directions without overshooting', () => {
    let l = single()
    l = insertBand(l, 1, 'b', 100)
    l = insertBand(l, 2, 'c', 100)
    const down = moveTileToBand(l, 'a', 2)
    expect(down.bands.map((b) => (b.node as TileLeaf).id)).toEqual(['b', 'a', 'c'])
    const up = moveTileToBand(l, 'c', 0)
    expect(up.bands.map((b) => (b.node as TileLeaf).id)).toEqual(['c', 'a', 'b'])
    expect(moveTileToBand(l, 'a', 0)).toBe(l)
    expect(moveTileToBand(l, 'a', 1)).toBe(l)
  })
})

describe('resizeDivider (row widths)', () => {
  it('redistributes the pair by pixel delta with a min clamp', () => {
    const l = splitAtTile(single(), 'a', 'e', 'b')
    const resized = resizeDivider(l, { band: 0, path: [], index: 0 }, 100, 1000, 40)
    assertValid(resized)
    const node = resized.bands[0]?.node as RowNode
    expect(node.ratios[0]).toBeCloseTo(0.6)
    const clamped = resizeDivider(l, { band: 0, path: [], index: 0 }, 10_000, 1000, 40)
    expect((clamped.bands[0]?.node as RowNode).ratios[1]).toBeCloseTo(0.04)
  })

  it('no-ops when the pair cannot host two minimums', () => {
    const l = splitAtTile(single(), 'a', 'e', 'b')
    expect(resizeDivider(l, { band: 0, path: [], index: 0 }, 10, 60, 40)).toBe(l)
  })
})

describe('stretchTileHeight', () => {
  it('grows exactly one tile; stacked and row neighbors never move', () => {
    const l = splitAtTile(splitAtTile(single(), 'a', 'e', 'b'), 'a', 's', 'c')
    const stretched = stretchTileHeight(l, 'a', 60, 64)
    assertValid(stretched)
    expect(getTile(stretched, 'a')?.h).toBe(160)
    expect(getTile(stretched, 'c')?.h).toBe(100)
    expect(getTile(stretched, 'b')?.h).toBe(200)
  })

  it('floors at minPx and returns identity on no-ops', () => {
    const l = single()
    expect(getTile(stretchTileHeight(l, 'a', -500, 64), 'a')?.h).toBe(64)
    expect(stretchTileHeight(l, 'a', 0, 64)).toBe(l)
    expect(stretchTileHeight(l, 'ghost', 10, 64)).toBe(l)
  })
})

describe('resizeStackPair (north negotiation)', () => {
  it('moves the shared boundary between stacked tiles, clamped both ways', () => {
    const l = splitAtTile(single(), 'a', 's', 'b')
    const moved = resizeStackPair(l, { band: 0, path: [], index: 0 }, 30, 40)
    expect(getTile(moved, 'a')?.h).toBe(130)
    expect(getTile(moved, 'b')?.h).toBe(70)
    const clamped = resizeStackPair(l, { band: 0, path: [], index: 0 }, 500, 40)
    expect(getTile(clamped, 'b')?.h).toBe(40)
  })

  it('declines when a side is a nested split', () => {
    const l = splitAtTile(splitAtTile(single(), 'a', 's', 'b'), 'b', 'e', 'c')
    expect(resizeStackPair(l, { band: 0, path: [], index: 0 }, 30, 40)).toBe(l)
  })
})

describe('geometry invariants', () => {
  it('never overlaps tiles, even with ragged column ends', () => {
    let l = single()
    l = splitAtTile(l, 'a', 'e', 'b')
    l = splitAtTile(l, 'b', 's', 'c')
    l = splitAtTile(l, 'a', 's', 'd')
    l = stretchTileHeight(l, 'd', 90, 64)
    l = insertBand(l, 1, 'e', 120)
    l = moveTile(l, 'c', 'a', 'w')
    assertValid(l)

    const geo = computeGeometry(l, 1200, 8)
    const rects = [...geo.tiles.values()]
    for (let i = 0; i < rects.length; i++) {
      for (let j = i + 1; j < rects.length; j++) {
        const a = rects[i] as { x: number; y: number; w: number; h: number }
        const b = rects[j] as { x: number; y: number; w: number; h: number }
        const overlap =
          a.x < b.x + b.w - 1e-6 &&
          b.x < a.x + a.w - 1e-6 &&
          a.y < b.y + b.h - 1e-6 &&
          b.y < a.y + a.h - 1e-6
        expect(overlap).toBe(false)
      }
    }
    expect(geo.totalHeight).toBeGreaterThan(0)
  })

  it('band heights derive from content', () => {
    const l = stretchTileHeight(splitAtTile(single(), 'a', 's', 'b'), 'b', 100, 64)
    expect(nodeHeight(l.bands[0]?.node as ColumnNode, 8)).toBe(100 + 8 + 200)
  })
})
