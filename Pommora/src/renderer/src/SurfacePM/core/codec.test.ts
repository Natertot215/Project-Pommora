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
              { kind: 'tile', id: 'b', h: 100 },
            ],
          },
        },
      ],
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
              { kind: 'tile', id: 'b', h: 100 },
            ],
          },
        },
      ],
    }
    expect(decodeLayout(raw)?.bands[0]?.node).toMatchObject({ ratios: [0.5, 0.5] })
  })

  it('collapses single-child splits and floors tile heights', () => {
    const raw = {
      bands: [
        {
          node: {
            kind: 'column',
            children: [{ kind: 'row', ratios: [1], children: [{ kind: 'tile', id: 'a', h: -9 }] }],
          },
        },
      ],
    }
    const l = decodeLayout(raw)
    expect(l?.bands[0]?.node).toEqual({ kind: 'tile', id: 'a', h: 32 })
  })

  it('rebuilds overflow ratios as uniform — a summed Infinity would zero them', () => {
    const raw = {
      bands: [
        {
          node: {
            kind: 'row',
            ratios: [1e308, 1e308],
            children: [
              { kind: 'tile', id: 'a', h: 100 },
              { kind: 'tile', id: 'b', h: 100 },
            ],
          },
        },
      ],
    }
    const l = decodeLayout(raw)
    expect(l?.bands[0]?.node).toMatchObject({ ratios: [0.5, 0.5] })
    expect(l && validateLayout(l)).toEqual([])
  })

  it('drops duplicate tile ids — later occurrences, the space closes', () => {
    const dup = {
      bands: [
        { node: { kind: 'tile', id: 'a', h: 100 } },
        { node: { kind: 'tile', id: 'a', h: 100 } },
      ],
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
              { kind: 'tile', id: 'x', h: 80 },
            ],
          },
        },
      ],
    }
    expect(decodeLayout(inRow)?.bands[0]?.node).toEqual({ kind: 'tile', id: 'x', h: 80 })
  })

  it('returns null only for the truly shapeless', () => {
    expect(decodeLayout(42)).toBeNull()
    expect(decodeLayout({ bands: 'no' })).toBeNull()
    expect(decodeLayout(null)).toBeNull()
  })

  it('salvages a broken tile height instead of rejecting — hand-edits happen', () => {
    const l = decodeLayout({ bands: [{ node: { kind: 'tile', id: 'a', h: Number.NaN } }] })
    expect(l?.bands[0]?.node).toEqual({ kind: 'tile', id: 'a', h: 32 })
    expect(
      decodeLayout({ bands: [{ node: { kind: 'tile', id: 'b', h: null } }] })?.bands,
    ).toHaveLength(1)
  })

  it('one malformed node never wipes the document — survivors keep their space', () => {
    const raw = {
      bands: [
        { node: { kind: 'tile', id: 'good1', h: 100 } },
        { node: { kind: 'tile', id: 'broken', h: null } },
        { node: { kind: 'what-even' } },
        {
          node: {
            kind: 'row',
            ratios: [0.5, 0.5],
            children: [
              { kind: 'tile', id: 'good2', h: 80 },
              { kind: 'tile', id: 'bad-child', h: 'tall' },
            ],
          },
        },
      ],
    }
    const l = decodeLayout(raw)
    expect(l).not.toBeNull()
    expect(l && validateLayout(l)).toEqual([])
    const ids = l ? l.bands.map((b) => JSON.stringify(b.node)) : []
    expect(ids.join()).toContain('good1')
    expect(ids.join()).toContain('good2')
    expect(ids.join()).toContain('broken') // height repaired, tile kept
    expect(ids.join()).not.toContain('what-even')
  })

  it('every repaired decode passes validateLayout — the completeness oracle', () => {
    const fixtures: unknown[] = [
      { bands: [] },
      {
        bands: [
          { node: { kind: 'tile', id: 'a', h: 100 } },
          { node: { kind: 'tile', id: 'a', h: 100 } },
        ],
      },
      {
        bands: [
          {
            node: {
              kind: 'row',
              ratios: [3, 0, 1],
              children: [
                { kind: 'tile', id: 'p', h: 1 },
                { kind: 'tile', id: 'q', h: 500 },
              ],
            },
          },
        ],
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
                    { kind: 'tile', id: 'n2', h: 40 },
                  ],
                },
              ],
            },
          },
        ],
      },
    ]
    for (const raw of fixtures) {
      const decoded = decodeLayout(raw)
      expect(decoded).not.toBeNull()
      expect(decoded && validateLayout(decoded)).toEqual([])
    }
  })
})
