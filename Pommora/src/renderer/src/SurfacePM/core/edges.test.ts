import { describe, expect, it } from 'vitest'
import { insertBand, splitAtTile } from './ops'
import { resolveEdge } from './edges'

// a | b over a full band, then b splits south into b/c, c splits east into c/d:
// band 0 root: row[a, column[b, row[c, d]]]
const build = () => {
  let l = insertBand({ bands: [] }, 0, 'a', 300)
  l = splitAtTile(l, 'a', 'e', 'b')
  l = splitAtTile(l, 'b', 's', 'c')
  l = splitAtTile(l, 'c', 'e', 'd')
  return l
}

describe('resolveEdge', () => {
  const l = build()

  it('resolves a direct sibling boundary', () => {
    expect(resolveEdge(l, 'a', 'e')).toEqual({
      kind: 'divider',
      ref: { band: 0, path: [], index: 0 }
    })
  })

  it('resolves through nested splits to the outer divider', () => {
    // c's west edge crosses the column split — the boundary is the root row divider.
    expect(resolveEdge(l, 'c', 'w')).toEqual({
      kind: 'divider',
      ref: { band: 0, path: [], index: 0 }
    })
  })

  it('resolves the nearest matching ancestor first', () => {
    // d's west edge is the c|d divider, not the root one.
    expect(resolveEdge(l, 'd', 'w')).toEqual({
      kind: 'divider',
      ref: { band: 0, path: [1, 1], index: 0 }
    })
    // c's north edge is the b|(c d) divider inside the column split.
    expect(resolveEdge(l, 'c', 'n')).toEqual({
      kind: 'divider',
      ref: { band: 0, path: [1], index: 0 }
    })
  })

  it('maps a bottom-most south edge to the band', () => {
    expect(resolveEdge(l, 'a', 's')).toEqual({ kind: 'band', band: 0 })
    expect(resolveEdge(l, 'c', 's')).toEqual({ kind: 'band', band: 0 })
  })

  it('returns null for outer edges that cannot resize', () => {
    expect(resolveEdge(l, 'a', 'w')).toBeNull()
    expect(resolveEdge(l, 'a', 'n')).toBeNull()
    expect(resolveEdge(l, 'b', 'n')).toBeNull()
    expect(resolveEdge(l, 'd', 'e')).toBeNull()
  })

  it('returns null for unknown tiles', () => {
    expect(resolveEdge(l, 'ghost', 'e')).toBeNull()
  })
})
