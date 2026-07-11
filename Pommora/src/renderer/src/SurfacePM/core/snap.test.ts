import { describe, expect, it } from 'vitest'
import { insertBand, splitAtTile } from './ops'
import { computeGeometry } from './rects'
import { snapAxis, xCandidates, yCandidates } from './snap'

describe('snapAxis', () => {
  it('locks to the nearest candidate inside the threshold, else passes through', () => {
    expect(snapAxis(103, [100, 200], 6)).toBe(100)
    expect(snapAxis(196, [100, 200], 6)).toBe(200)
    expect(snapAxis(150, [100, 200], 6)).toBe(150)
    expect(snapAxis(103, [], 6)).toBe(103)
  })

  it('prefers the closest of several candidates', () => {
    expect(snapAxis(104, [100, 106], 6)).toBe(106)
  })
})

describe('candidates', () => {
  it('collects tile edge positions, deduplicated', () => {
    let l = insertBand({ bands: [] }, 0, 'a', 200)
    l = splitAtTile(l, 'a', 'e', 'b')
    l = insertBand(l, 1, 'c', 100)
    const geo = computeGeometry(l, 1000, 8)
    const xs = xCandidates(geo)
    const ys = yCandidates(geo)
    expect(xs).toContain(0)
    expect(xs).toContain(1000)
    expect(xs).toContain(496)
    expect(ys).toContain(0)
    expect(ys).toContain(200)
    expect(ys).toContain(208)
    expect(ys).toContain(308)
    expect(new Set(xs).size).toBe(xs.length)
  })

  it('keeps raw positions — a snap must land exactly on a fractional edge', () => {
    let l = insertBand({ bands: [] }, 0, 'a', 200)
    l = splitAtTile(l, 'a', 'e', 'b', 1 / 3)
    const geo = computeGeometry(l, 1000, 8)
    const a = geo.tiles.get('a')
    if (!a) throw new Error('missing tile')
    const aRight = a.x + a.w
    expect(Number.isInteger(aRight)).toBe(false)
    expect(xCandidates(geo)).toContain(aRight)
  })
})
