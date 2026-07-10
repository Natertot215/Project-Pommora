import { describe, expect, it } from 'vitest'
import { validateLayout } from './model'
import { insertBand, splitAtTile } from './ops'
import { decodeLayout, encodeLayout } from './codec'

describe('codec', () => {
  it('round-trips a real layout', () => {
    const l = splitAtTile(insertBand({ bands: [] }, 0, 'a', 200), 'a', 'e', 'b', 0.3)
    expect(decodeLayout(encodeLayout(l))).toEqual(l)
  })

  it('repairs drifted ratios by renormalizing', () => {
    const raw = {
      bands: [
        {
          height: 200,
          node: {
            kind: 'split',
            dir: 'row',
            ratios: [2, 2],
            children: [
              { kind: 'tile', id: 'a' },
              { kind: 'tile', id: 'b' }
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
          height: 120,
          node: {
            kind: 'split',
            dir: 'column',
            ratios: [1],
            children: [
              { kind: 'tile', id: 'a' },
              { kind: 'tile', id: 'b' }
            ]
          }
        }
      ]
    }
    expect(decodeLayout(raw)?.bands[0]?.node).toMatchObject({ ratios: [0.5, 0.5] })
  })

  it('collapses a single-child split and floors band heights', () => {
    const raw = {
      bands: [
        {
          height: -5,
          node: { kind: 'split', dir: 'row', ratios: [1], children: [{ kind: 'tile', id: 'a' }] }
        }
      ]
    }
    const l = decodeLayout(raw)
    expect(l?.bands[0]).toMatchObject({ height: 80, node: { kind: 'tile', id: 'a' } })
  })

  it('returns null for garbage', () => {
    expect(decodeLayout(42)).toBeNull()
    expect(decodeLayout({ bands: 'no' })).toBeNull()
    expect(decodeLayout(null)).toBeNull()
  })

  it('drops duplicate tile ids — later occurrences, space absorbed', () => {
    const dupAcrossBands = {
      bands: [
        { height: 200, node: { kind: 'tile', id: 'a' } },
        { height: 200, node: { kind: 'tile', id: 'a' } }
      ]
    }
    expect(decodeLayout(dupAcrossBands)?.bands).toHaveLength(1)

    const dupInSplit = {
      bands: [
        {
          height: 200,
          node: {
            kind: 'split',
            dir: 'row',
            ratios: [0.5, 0.5],
            children: [
              { kind: 'tile', id: 'x' },
              { kind: 'tile', id: 'x' }
            ]
          }
        }
      ]
    }
    expect(decodeLayout(dupInSplit)?.bands[0]?.node).toEqual({ kind: 'tile', id: 'x' })
  })

  it('every repaired decode passes validateLayout — the completeness oracle', () => {
    const fixtures: unknown[] = [
      { bands: [] },
      {
        bands: [
          { height: 200, node: { kind: 'tile', id: 'a' } },
          { height: 200, node: { kind: 'tile', id: 'a' } }
        ]
      },
      {
        bands: [
          {
            height: -1,
            node: {
              kind: 'split',
              dir: 'row',
              ratios: [3, 0, 1],
              children: [
                { kind: 'tile', id: 'p' },
                { kind: 'tile', id: 'q' }
              ]
            }
          }
        ]
      },
      {
        bands: [
          {
            height: 50,
            node: {
              kind: 'split',
              dir: 'column',
              ratios: [1],
              children: [
                {
                  kind: 'split',
                  dir: 'row',
                  ratios: [1],
                  children: [{ kind: 'tile', id: 'solo' }]
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
