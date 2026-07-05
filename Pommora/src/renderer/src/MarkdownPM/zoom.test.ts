import { describe, it, expect } from 'vitest'
import { zoomFontSize, zoomMultiplier, clampZoom, EDITOR_BASE_PT } from './zoom'

describe('editor zoom mapping (2^(z-1))', () => {
  it('1.0 is the 15pt base (1×)', () => {
    expect(zoomMultiplier(1)).toBe(1)
    expect(zoomFontSize(1)).toBe(EDITOR_BASE_PT)
  })
  it('0.0 is 2× smaller (0.5× → 7.5pt)', () => {
    expect(zoomMultiplier(0)).toBe(0.5)
    expect(zoomFontSize(0)).toBe(7.5)
  })
  it('2.0 is 2× larger (2× → 30pt)', () => {
    expect(zoomMultiplier(2)).toBe(2)
    expect(zoomFontSize(2)).toBe(30)
  })
  it('clamps out-of-range values to [0, 2]', () => {
    expect(clampZoom(-1)).toBe(0)
    expect(clampZoom(3)).toBe(2)
    expect(zoomFontSize(5)).toBe(30)
  })
})
