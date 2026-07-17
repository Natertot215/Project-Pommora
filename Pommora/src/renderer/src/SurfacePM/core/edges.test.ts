import { describe, expect, it } from 'vitest'
import { insertBand, splitAtTile } from './ops'
import { resolveEdge } from './edges'

// row[ a, column[b, row[c, d]] ] — a beside a stack of b over (c|d).
const build = () => {
  let l = insertBand({ bands: [] }, 0, 'a', 300)
  l = splitAtTile(l, 'a', 'e', 'b')
  l = splitAtTile(l, 'b', 's', 'c')
  l = splitAtTile(l, 'c', 'e', 'd')
  return l
}

describe('resolveEdge', () => {
  const l = build()

  it('east/west resolve to the nearest row divider', () => {
    expect(resolveEdge(l, 'a', 'e')).toEqual({
      kind: 'divider',
      ref: { band: 0, path: [], index: 0 },
    })
    expect(resolveEdge(l, 'c', 'w')).toEqual({
      kind: 'divider',
      ref: { band: 0, path: [], index: 0 },
    })
    expect(resolveEdge(l, 'd', 'w')).toEqual({
      kind: 'divider',
      ref: { band: 0, path: [1, 1], index: 0 },
    })
  })

  it('north resolves to the stacked boundary above', () => {
    expect(resolveEdge(l, 'c', 'n')).toEqual({
      kind: 'stack',
      ref: { band: 0, path: [1], index: 0 },
    })
    expect(resolveEdge(l, 'd', 'n')).toEqual({
      kind: 'stack',
      ref: { band: 0, path: [1], index: 0 },
    })
  })

  it('south never resolves — it stretches instead', () => {
    expect(resolveEdge(l, 'a', 's')).toBeNull()
    expect(resolveEdge(l, 'c', 's')).toBeNull()
  })

  it('outer edges that cannot resize return null', () => {
    expect(resolveEdge(l, 'a', 'w')).toBeNull()
    expect(resolveEdge(l, 'a', 'n')).toBeNull()
    expect(resolveEdge(l, 'b', 'n')).toBeNull()
    expect(resolveEdge(l, 'd', 'e')).toBeNull()
    expect(resolveEdge(l, 'ghost', 'e')).toBeNull()
  })

  it('a full-width block negotiates the band seam when both roots are tiles', () => {
    let bands = insertBand({ bands: [] }, 0, 'top', 200)
    bands = insertBand(bands, 1, 'bottom', 160)
    expect(resolveEdge(bands, 'bottom', 'n')).toEqual({ kind: 'bandpair', above: 0 })
    expect(resolveEdge(bands, 'top', 'n')).toBeNull() // first band — nothing above

    // a split band above declines — no single height to give
    const splitAbove = insertBand(
      splitAtTile(insertBand({ bands: [] }, 0, 'x', 200), 'x', 'e', 'y'),
      1,
      'z',
      160,
    )
    expect(resolveEdge(splitAbove, 'z', 'n')).toBeNull()
  })
})
