import { describe, expect, it } from 'vitest'
import type { SurfaceLayout } from './model'
import { findTile, tileIds, validateLayout } from './model'
import {
  insertBand,
  moveTile,
  moveTileToBand,
  removeTile,
  resizeBand,
  resizeDivider,
  splitAtTile
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
    expect(insertBand(l1, 0, 'a', 100)).toBe(l1)
  })

  it('clamps the index', () => {
    const l = insertBand(single(), 99, 'b', 100)
    expect(l.bands[1]?.node).toEqual({ kind: 'tile', id: 'b' })
  })
})

describe('splitAtTile', () => {
  it('splits east: target keeps the left, new tile the right', () => {
    const l = splitAtTile(single(), 'a', 'e', 'b')
    assertValid(l)
    const node = l.bands[0]?.node
    expect(node).toMatchObject({
      kind: 'split',
      dir: 'row',
      children: [
        { kind: 'tile', id: 'a' },
        { kind: 'tile', id: 'b' }
      ]
    })
  })

  it('splits west and north with the new tile first', () => {
    const w = splitAtTile(single(), 'a', 'w', 'b')
    expect((w.bands[0]?.node as { children: { id: string }[] }).children[0]?.id).toBe('b')
    const n = splitAtTile(single(), 'a', 'n', 'b')
    expect(n.bands[0]?.node).toMatchObject({ dir: 'column' })
    expect((n.bands[0]?.node as { children: { id: string }[] }).children[0]?.id).toBe('b')
  })

  it('splices as a sibling when the parent splits the same way — no degenerate nesting', () => {
    const l = splitAtTile(splitAtTile(single(), 'a', 'e', 'b'), 'b', 'e', 'c')
    assertValid(l)
    const node = l.bands[0]?.node as { children: { id: string }[]; ratios: number[] }
    expect(node.children.map((c) => c.id)).toEqual(['a', 'b', 'c'])
    expect(node.ratios[0]).toBeCloseTo(0.5)
    expect(node.ratios[1]).toBeCloseTo(0.25)
    expect(node.ratios[2]).toBeCloseTo(0.25)
  })

  it('nests when the direction differs', () => {
    const l = splitAtTile(splitAtTile(single(), 'a', 'e', 'b'), 'b', 's', 'c')
    assertValid(l)
    const root = l.bands[0]?.node as { children: unknown[] }
    expect(root.children[1]).toMatchObject({ kind: 'split', dir: 'column' })
  })

  it('rejects unknown targets and duplicate ids', () => {
    const l = single()
    expect(splitAtTile(l, 'ghost', 'e', 'b')).toBe(l)
    expect(splitAtTile(l, 'a', 'e', 'a')).toBe(l)
  })
})

describe('removeTile', () => {
  it('lets the sibling absorb the space and collapses the split', () => {
    const l = removeTile(splitAtTile(single(), 'a', 'e', 'b'), 'b')
    assertValid(l)
    expect(l.bands[0]?.node).toEqual({ kind: 'tile', id: 'a' })
  })

  it('renormalizes ratios among 3+ siblings', () => {
    const three = splitAtTile(splitAtTile(single(), 'a', 'e', 'b'), 'b', 'e', 'c')
    const l = removeTile(three, 'a')
    assertValid(l)
    const node = l.bands[0]?.node as { ratios: number[] }
    expect(node.ratios.reduce((s, r) => s + r, 0)).toBeCloseTo(1)
  })

  it('drops a band whose only tile is removed', () => {
    const l = removeTile(insertBand(single(), 1, 'b', 100), 'b')
    assertValid(l)
    expect(l.bands).toHaveLength(1)
  })

  it('collapses through nested splits', () => {
    const nested = splitAtTile(splitAtTile(single(), 'a', 'e', 'b'), 'b', 's', 'c')
    const l = removeTile(nested, 'c')
    assertValid(l)
    expect(tileIds(l)).toEqual(['a', 'b'])
  })
})

describe('moveTile', () => {
  it('relocates across the tree, tessellation intact', () => {
    const three = splitAtTile(splitAtTile(single(), 'a', 'e', 'b'), 'b', 's', 'c')
    const l = moveTile(three, 'c', 'a', 'n')
    assertValid(l)
    expect(tileIds(l).sort()).toEqual(['a', 'b', 'c'])
    expect(findTile(l, 'c')).toBeDefined()
  })

  it('no-ops on self-drop and unknown ids', () => {
    const l = splitAtTile(single(), 'a', 'e', 'b')
    expect(moveTile(l, 'a', 'a', 'e')).toBe(l)
    expect(moveTile(l, 'ghost', 'a', 'e')).toBe(l)
  })

  it('moves a tile out into its own band', () => {
    const l = moveTileToBand(splitAtTile(single(), 'a', 'e', 'b'), 'b', 1, 150)
    assertValid(l)
    expect(l.bands).toHaveLength(2)
    expect(l.bands[0]?.node).toEqual({ kind: 'tile', id: 'a' })
  })

  it('reorders a whole band downward without overshooting', () => {
    let l = insertBand(single(), 1, 'b', 100)
    l = insertBand(l, 2, 'c', 100)
    const moved = moveTileToBand(l, 'a', 2, 160)
    assertValid(moved)
    expect(moved.bands.map((b) => (b.node as { id: string }).id)).toEqual(['b', 'a', 'c'])
  })

  it('reorders a whole band upward at the stated index', () => {
    let l = insertBand(single(), 1, 'b', 100)
    l = insertBand(l, 2, 'c', 100)
    const moved = moveTileToBand(l, 'c', 0, 160)
    assertValid(moved)
    expect(moved.bands.map((b) => (b.node as { id: string }).id)).toEqual(['c', 'a', 'b'])
  })
})

describe('resizeDivider', () => {
  it('redistributes the pair by pixel delta', () => {
    const l = splitAtTile(single(), 'a', 'e', 'b')
    const resized = resizeDivider(l, { band: 0, path: [], index: 0 }, 100, 1000, 40)
    assertValid(resized)
    const node = resized.bands[0]?.node as { ratios: number[] }
    expect(node.ratios[0]).toBeCloseTo(0.6)
    expect(node.ratios[1]).toBeCloseTo(0.4)
  })

  it('clamps both sides to the minimum', () => {
    const l = splitAtTile(single(), 'a', 'e', 'b')
    const resized = resizeDivider(l, { band: 0, path: [], index: 0 }, 10_000, 1000, 40)
    const node = resized.bands[0]?.node as { ratios: number[] }
    expect(node.ratios[1]).toBeCloseTo(0.04)
  })

  it('no-ops when the pair cannot host two minimums', () => {
    const l = splitAtTile(single(), 'a', 'e', 'b')
    expect(resizeDivider(l, { band: 0, path: [], index: 0 }, 10, 60, 40)).toBe(l)
  })
})

describe('resizeBand', () => {
  it('grows and floors at the minimum', () => {
    const l = single()
    expect(resizeBand(l, 0, 50, 80).bands[0]?.height).toBe(250)
    expect(resizeBand(l, 0, -500, 80).bands[0]?.height).toBe(80)
  })
})

describe('tessellation invariant (geometry)', () => {
  it('covers every band exactly — no holes, no overlap', () => {
    let l = single()
    l = splitAtTile(l, 'a', 'e', 'b')
    l = splitAtTile(l, 'b', 's', 'c')
    l = splitAtTile(l, 'a', 's', 'd')
    l = insertBand(l, 1, 'e', 120)
    l = moveTile(l, 'd', 'c', 'w')
    assertValid(l)

    const geo = computeGeometry(l, 1200, 0)
    const rects = [...geo.tiles.values()]
    const area = rects.reduce((s, r) => s + r.w * r.h, 0)
    const bandArea = l.bands.reduce((s, b) => s + 1200 * b.height, 0)
    expect(area).toBeCloseTo(bandArea, 4)

    for (let i = 0; i < rects.length; i++) {
      for (let j = i + 1; j < rects.length; j++) {
        const a = rects[i]!
        const b = rects[j]!
        const overlap =
          a.x < b.x + b.w - 1e-6 &&
          b.x < a.x + a.w - 1e-6 &&
          a.y < b.y + b.h - 1e-6 &&
          b.y < a.y + a.h - 1e-6
        expect(overlap).toBe(false)
      }
    }
  })

  it('emits divider hit zones with the split extent attached', () => {
    const l = splitAtTile(single(), 'a', 'e', 'b')
    const geo = computeGeometry(l, 1000, 8)
    expect(geo.dividers).toHaveLength(1)
    expect(geo.dividers[0]?.dir).toBe('row')
    expect(geo.dividers[0]?.extentPx).toBeCloseTo(992)
  })
})
