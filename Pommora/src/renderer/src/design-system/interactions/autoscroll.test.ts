import { describe, expect, it, vi } from 'vitest'
import { autoScroll, clampToLimit, dampen, edgeVelocity, gateIntent, scrollableInAxis, stepPixels, type Intent, type Params } from './autoscroll'

const P: Params = { edge: 48, speed: 840, ramp: 2, dampenMs: 300 }

describe('edgeVelocity — proximity ramp', () => {
  it('is 0 away from any edge', () => {
    expect(edgeVelocity(0, 300, 150, P)).toBe(0)
  })
  it('is positive nearing the high edge, negative nearing the low edge', () => {
    expect(edgeVelocity(0, 300, 295, P)).toBeGreaterThan(0)
    expect(edgeVelocity(0, 300, 5, P)).toBeLessThan(0)
  })
  it('ramps up as the point gets closer to the edge', () => {
    const near = Math.abs(edgeVelocity(0, 300, 299, P)) // 1px from edge
    const far = Math.abs(edgeVelocity(0, 300, 260, P)) // ~40px in
    expect(near).toBeGreaterThan(far)
  })
  it('caps at full speed past the edge (no viewport clamp needed)', () => {
    expect(edgeVelocity(0, 300, 400, P)).toBe(P.speed) // 100px past the high edge → max
  })
})

describe('dampen — time ramp from drag start', () => {
  it('is 0 at t=0 and 1 after the window', () => {
    expect(dampen(0, 300)).toBe(0)
    expect(dampen(300, 300)).toBe(1)
    expect(dampen(600, 300)).toBe(1)
  })
  it('is 1 when the window is 0', () => {
    expect(dampen(0, 0)).toBe(1)
  })
})

describe('clampToLimit — no churn at a maxed edge', () => {
  it('zeroes upward scroll at the top', () => {
    expect(clampToLimit(-5, 0, 800)).toBe(0)
  })
  it('zeroes downward scroll at the bottom', () => {
    expect(clampToLimit(5, 800, 800)).toBe(0)
  })
  it('passes velocity through in the middle', () => {
    expect(clampToLimit(5, 400, 800)).toBe(5)
  })
})

describe('stepPixels — sub-pixel accumulation', () => {
  it('carries the fractional remainder so a slow ramp eventually scrolls', () => {
    const a = stepPixels(30, 16, 0) // 30px/s * 0.016s = 0.48px → 0px, 0.48 carried
    expect(a.px).toBe(0)
    const b = stepPixels(30, 16, a.frac) // 0.48 + 0.48 = 0.96 → 0px, 0.96 carried
    expect(b.px).toBe(0)
    const c = stepPixels(30, 16, b.frac) // 0.96 + 0.48 = 1.44 → 1px scrolls
    expect(c.px).toBe(1)
  })
})

describe('gateIntent — direction-intent', () => {
  it('blocks a direction until the pointer has left that band once', () => {
    const intent: Intent = { up: false, down: false, left: false, right: false }
    // Grab pinned at the bottom edge: downward velocity, down not yet armed → blocked.
    expect(gateIntent(intent, 0, 10).vy).toBe(0)
    // Pointer moves up out of the band (vy <= 0 arms down) …
    gateIntent(intent, 0, -10)
    // … now a downward push is allowed.
    expect(gateIntent(intent, 0, 10).vy).toBe(10)
  })
})

// The back-compat shim ships to 3 live drag surfaces until they migrate. The helper tests above cover
// the math in isolation but NOT the shim's wiring (scrollBy arg order + which rect edge maps to which
// axis) — a bug class isolated tests structurally can't see. These pin it end-to-end.
describe('autoScroll shim — wiring (arg order + axis mapping)', () => {
  const mock = (over: Partial<Record<string, number>> = {}): { el: HTMLElement; scrollBy: ReturnType<typeof vi.fn> } => {
    const scrollBy = vi.fn()
    const el = {
      getBoundingClientRect: () => ({ top: 100, bottom: 300, left: 0, right: 200, width: 200, height: 200 }),
      scrollTop: 50,
      scrollLeft: 50,
      scrollHeight: 1000,
      clientHeight: 200,
      scrollWidth: 1000,
      clientWidth: 200,
      scrollBy,
      ...over
    } as unknown as HTMLElement
    return { el, scrollBy }
  }
  it('does not scroll away from any edge', () => {
    const { el, scrollBy } = mock()
    expect(autoScroll(el, 100, 200)).toBe(false)
    expect(scrollBy).not.toHaveBeenCalled()
  })
  it('scrolls DOWN (positive y, the 2nd scrollBy arg) near the bottom edge', () => {
    const { el, scrollBy } = mock()
    expect(autoScroll(el, 100, 295)).toBe(true)
    expect(scrollBy.mock.calls[0][1]).toBeGreaterThan(0)
  })
  it('scrolls UP (negative y) near the top edge', () => {
    const { el, scrollBy } = mock()
    expect(autoScroll(el, 100, 105)).toBe(true)
    expect(scrollBy.mock.calls[0][1]).toBeLessThan(0)
  })
  it('scrolls RIGHT (positive x, the 1st scrollBy arg) near the right edge', () => {
    const { el, scrollBy } = mock()
    expect(autoScroll(el, 195, 200)).toBe(true)
    expect(scrollBy.mock.calls[0][0]).toBeGreaterThan(0)
  })
  it('does NOT scroll past the bottom limit', () => {
    const { el, scrollBy } = mock({ scrollTop: 800 }) // scrollHeight(1000) - clientHeight(200)
    expect(autoScroll(el, 100, 295)).toBe(false)
    expect(scrollBy).not.toHaveBeenCalled()
  })
})

describe('scrollableInAxis', () => {
  const over = { scrollWidth: 1000, clientWidth: 200, scrollHeight: 1000, clientHeight: 200 }
  it('detects a y-scroller and rejects it for the x axis', () => {
    expect(scrollableInAxis('hidden', 'auto', over, 'y')).toBe(true)
    expect(scrollableInAxis('hidden', 'auto', over, 'x')).toBe(false)
  })
  it('detects an x-only scroller only for x / xy', () => {
    expect(scrollableInAxis('auto', 'hidden', over, 'x')).toBe(true)
    expect(scrollableInAxis('auto', 'hidden', over, 'y')).toBe(false)
    expect(scrollableInAxis('auto', 'hidden', over, 'xy')).toBe(true)
  })
  it('requires actual overflow, not just an overflow style', () => {
    const noOverflow = { scrollWidth: 200, clientWidth: 200, scrollHeight: 200, clientHeight: 200 }
    expect(scrollableInAxis('auto', 'auto', noOverflow, 'xy')).toBe(false)
  })
})
