import { describe, expect, it } from 'vitest'
import { DEFAULT_ZOOM, ZOOM_STEPS, zoomStep } from './blockZoom'

describe('blockZoom', () => {
  it('has the five ratified factors, high to low', () => {
    expect(ZOOM_STEPS.map((s) => s.factor)).toEqual([1.25, 1, 0.85, 0.65, 0.5])
  })

  it('derives cls (padded, 1.0 has none), and both spellings', () => {
    expect(zoomStep(1)).toMatchObject({ factor: DEFAULT_ZOOM, cls: '', inline: '1x', label: '1.00x' })
    expect(zoomStep(0.85)).toMatchObject({ cls: 'blk-zoom-085', inline: '0.85x', label: '0.85x' })
    expect(zoomStep(0.5)).toMatchObject({ cls: 'blk-zoom-050', inline: '0.5x', label: '0.50x' })
    expect(zoomStep(1.25).cls).toBe('blk-zoom-125')
  })

  it('resolves an absent factor to the 1.0 step', () => {
    expect(zoomStep(undefined).factor).toBe(1)
  })

  it('snaps an off-grid factor to the nearest step (hand-edit / import safety)', () => {
    expect(zoomStep(0.77).factor).toBe(0.85) // closer to 0.85 than 0.65
    expect(zoomStep(0.6).factor).toBe(0.65)
    expect(zoomStep(2).factor).toBe(1.25) // above the max clamps down
    expect(zoomStep(0.1).factor).toBe(0.5) // below the min clamps up
  })
})
