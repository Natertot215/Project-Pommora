import { describe, expect, it } from 'vitest'
import { validateLayout } from './model'
import { insertBand, splitAtTile } from './ops'
import { decodeLayout, encodeLayout } from './codec'

describe('codec', () => {
  it('round-trips a real layout', () => {
    const l = splitAtTile(insertBand({ bands: [] }, 0, 'a', 200), 'a', 'e', 'b', 0.3)
    expect(decodeLayout(encodeLayout(l))).toEqual(l)
  })

  it('repairs drifted row ratios by renormalizing', () => {
    const raw = {
      bands: [
        {
          node: {
            kind: 'row',
            ratios: [2, 2],
            children: [
              { kind: 'tile', id: 'a', h: 100 },
              { kind: 'tile', id: 'b', h: 100 }
            ]
          }
        }
      ]
    }
    const l = decodeLayout(raw)
    expect(l && validateLayout(l)).toEqual([])
    expect(l?.bands[0]?.node).toMatchObject({ ratios: [0.5, 0.5] })
  })

  it('rebuilds a ratio/children count mismatch as uniform', () => {
    const raw = {
      bands: [
        {
          node: {
            kind: 'row',
            ratios: [1],
            children: [
              { kind: 'tile', id: 'a', h: 100 },
              { kind: 'tile', id: 'b', h: 100 }
            ]
          }
        }
      ]
    }
    expect(decodeLayout(raw)?.bands[0]?.node).toMatchObject({ ratios: [0.5, 0.5] })
  })

  it('collapses single-child splits and floors tile heights', () => {
    const raw = {
      bands: [
        {
          node: {
            kind: 'column',
            children: [{ kind: 'row', ratios: [1], children: [{ kind: 'tile', id: 'a', h: -9 }] }]
          }
        }
      ]
    }
    const l = decodeLayout(raw)
    expect(l?.bands[0]?.node).toEqual({ kind: 'tile', id: 'a', h: 32 })
  })

  it('drops duplicate tile ids — later occurrences, the space closes', () => {
    const dup = {
      bands: [
        { node: { kind: 'tile', id: 'a', h: 100 } },
        { node: { kind: 'tile', id: 'a', h: 100 } }
      ]
    }
    expect(decodeLayout(dup)?.bands).toHaveLength(1)

    const inRow = {
      bands: [
        {
          node: {
            kind: 'row',
            ratios: [0.5, 0.5],
            children: [
              { kind: 'tile', id: 'x', h: 80 },
              { kind: 'tile', id: 'x', h: 80 }
            ]
          }
        }
      ]
    }
    expect(decodeLayout(inRow)?.bands[0]?.node).toEqual({ kind: 'tile', id: 'x', h: 80 })
  })

  it('returns null for garbage', () => {
    expect(decodeLayout(42)).toBeNull()
    expect(decodeLayout({ bands: 'no' })).toBeNull()
    expect(decodeLayout(null)).toBeNull()
    expect(decodeLayout({ bands: [{ node: { kind: 'tile', id: 'a', h: Number.NaN } }] })).toBeNull()
  })

  it('every repaired decode passes validateLayout — the completeness oracle', () => {
    const fixtures: unknown[] = [
      { bands: [] },
      {
        bands: [
          { node: { kind: 'tile', id: 'a', h: 100 } },
          { node: { kind: 'tile', id: 'a', h: 100 } }
        ]
      },
      {
        bands: [
          {
            node: {
              kind: 'row',
              ratios: [3, 0, 1],
              children: [
                { kind: 'tile', id: 'p', h: 1 },
                { kind: 'tile', id: 'q', h: 500 }
              ]
            }
          }
        ]
      },
      {
        bands: [
          {
            node: {
              kind: 'column',
              children: [
                { kind: 'tile', id: 'solo', h: 40 },
                {
                  kind: 'column',
                  children: [
                    { kind: 'tile', id: 'n1', h: 40 },
                    { kind: 'tile', id: 'n2', h: 40 }
                  ]
                }
              ]
            }
          }
        ]
      }
    ]
    for (const raw of fixtures) {
      const decoded = decodeLayout(raw)
      expect(decoded).not.toBeNull()
      expect(decoded && validateLayout(decoded)).toEqual([])
    }
  })
})
