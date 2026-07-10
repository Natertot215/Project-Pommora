import { describe, expect, it } from 'vitest'
import { insertBand } from './ops'
import { computeGeometry } from './rects'
import { hitTest } from './hitTest'

// Two full-width bands, 200px each, gap 8: band a occupies y 0-200, the gap is
// [200, 208] (seam centerline 204), band b occupies y 208-408, totalHeight 408.
const two = insertBand(insertBand({ bands: [] }, 0, 'a', 200), 1, 'b', 200)
const geo = computeGeometry(two, 1000, 8)

describe('hitTest', () => {
  it('targets a tile edge by nearest normalized distance', () => {
    expect(hitTest(geo, two, 'b', 950, 100)).toEqual({ kind: 'tile', id: 'a', edge: 'e' })
    expect(hitTest(geo, two, 'b', 500, 15)).toEqual({ kind: 'tile', id: 'a', edge: 'n' })
  })

  it('targets the seam between bands as a band insertion', () => {
    expect(hitTest(geo, two, 'b', 500, 204)).toEqual({ kind: 'band', index: 1 })
    expect(hitTest(geo, two, 'b', 500, 197)).toEqual({ kind: 'band', index: 1 })
  })

  it('targets above the first band as index 0', () => {
    expect(hitTest(geo, two, 'b', 500, -2)).toEqual({ kind: 'band', index: 0 })
    expect(hitTest(geo, two, 'b', 500, 4)).toEqual({ kind: 'band', index: 0 })
  })

  it('targets past the bottom as an append', () => {
    expect(hitTest(geo, two, 'a', 500, geo.totalHeight + 10)).toEqual({ kind: 'band', index: 2 })
  })

  it('never targets the dragged tile itself', () => {
    expect(hitTest(geo, two, 'a', 500, 100)).toBeNull()
  })

  it('scales its zones with bandZonePx without swallowing tile centers', () => {
    expect(hitTest(geo, two, 'b', 500, 180, 28)).toEqual({ kind: 'band', index: 1 })
    expect(hitTest(geo, two, 'b', 500, 60, 28)).toEqual({ kind: 'tile', id: 'a', edge: 'n' })
  })
})
