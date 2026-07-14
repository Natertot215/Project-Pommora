// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { autoScroll, clampToLimit, dampen, edgeVelocity, gateIntent, scrollableInAxis, startAutoScroll, stepPixels, stopAutoScroll, type Intent, type Params } from './autoscroll'

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

describe('startAutoScroll / stopAutoScroll — loop lifecycle', () => {
  // A faithful rAF fake: ids map to callbacks and cancelAnimationFrame actually removes them (a no-op
  // cancel would let an abandoned loop keep driving, hiding the one-driver invariant). The clock is
  // MONOTONIC across every flush so dt is always positive and a real stall can be simulated.
  let rafMap: Map<number, (ts: number) => void>
  let rafId: number
  let clock: number

  const fakeScroller = (): { el: HTMLElement; scrolls: () => number } => {
    let top = 400
    const el = {
      getBoundingClientRect: () => ({ top: 0, bottom: 300, left: 0, right: 300, width: 300, height: 300 }),
      get scrollTop() {
        return top
      },
      set scrollTop(v: number) {
        top = v
      },
      scrollLeft: 0,
      scrollHeight: 1000,
      clientHeight: 300,
      scrollWidth: 300,
      clientWidth: 300,
      scrollBy: (_x: number, y: number) => {
        top += y
      }
    } as unknown as HTMLElement
    return { el, scrolls: () => top }
  }

  const flush = (times: number, stepMs = 16): void => {
    for (let i = 0; i < times; i++) {
      const pending = [...rafMap.values()]
      rafMap = new Map()
      clock += stepMs
      for (const cb of pending) cb(clock)
    }
  }

  beforeEach(() => {
    rafMap = new Map()
    rafId = 0
    clock = 0
    vi.stubGlobal('requestAnimationFrame', (cb: (ts: number) => void) => {
      const id = ++rafId
      rafMap.set(id, cb)
      return id
    })
    vi.stubGlobal('cancelAnimationFrame', (id: number) => {
      rafMap.delete(id)
    })
  })
  afterEach(() => {
    stopAutoScroll()
    vi.unstubAllGlobals()
  })

  // Direction-intent means a drag that STARTS pinned at the edge never scrolls — the pointer must have
  // been out of that band once. Every test that needs actual scrolling starts at y=150 (out of the
  // bottom band, arms `down`), then moves to y=299 (into it) and holds past the dampen window.
  const doc = document.documentElement

  it('scrolls the fixed scroller toward the edge the point holds near', () => {
    const { el, scrolls } = fakeScroller()
    let y = 150
    startAutoScroll({ getPoint: () => ({ x: 150, y }), scroller: el, dragEl: doc, axis: 'y' })
    flush(3)
    const before = scrolls()
    y = 299
    flush(40)
    expect(scrolls()).toBeGreaterThan(before)
  })

  it('does NOT scroll when the drag starts pinned at the edge (direction-intent anti-rocket)', () => {
    const { el, scrolls } = fakeScroller()
    startAutoScroll({ getPoint: () => ({ x: 150, y: 299 }), scroller: el, dragEl: doc, axis: 'y' })
    flush(40)
    expect(scrolls()).toBe(400) // never armed `down` → never scrolled
  })

  it('stopAutoScroll halts the loop — no further scrolling', () => {
    const { el, scrolls } = fakeScroller()
    let y = 150
    startAutoScroll({ getPoint: () => ({ x: 150, y }), scroller: el, dragEl: doc, axis: 'y' })
    flush(3)
    y = 299
    flush(20)
    expect(scrolls()).toBeGreaterThan(400) // it was actively scrolling
    stopAutoScroll()
    const settled = scrolls()
    flush(30)
    expect(scrolls()).toBe(settled) // and stopped dead
  })

  it('a blur event stops the loop (backstop against a leaked rAF)', () => {
    const { el, scrolls } = fakeScroller()
    let y = 150
    startAutoScroll({ getPoint: () => ({ x: 150, y }), scroller: el, dragEl: doc, axis: 'y' })
    flush(3)
    y = 299
    flush(20)
    expect(scrolls()).toBeGreaterThan(400)
    window.dispatchEvent(new Event('blur'))
    const settled = scrolls()
    flush(30)
    expect(scrolls()).toBe(settled)
  })

  it('a second start replaces the first (singleton — one drag at a time)', () => {
    const a = fakeScroller()
    const b = fakeScroller()
    let y = 150
    startAutoScroll({ getPoint: () => ({ x: 150, y }), scroller: a.el, dragEl: doc, axis: 'y' })
    flush(3)
    y = 299
    flush(20)
    const aBeforeReplace = a.scrolls()
    expect(aBeforeReplace).toBeGreaterThan(400) // A was driven
    // Replace with B — a fresh loop with fresh intent, so re-arm it out of the band, then into it.
    startAutoScroll({ getPoint: () => ({ x: 150, y }), scroller: b.el, dragEl: doc, axis: 'y' })
    expect(rafMap.size).toBe(1) // the one-driver invariant: A's rAF was actually cancelled, not orphaned
    y = 150
    flush(3)
    y = 299
    flush(20)
    expect(a.scrolls()).toBe(aBeforeReplace) // A is abandoned — frozen since the replace
    expect(b.scrolls()).toBeGreaterThan(400) // B is now the one being driven
    expect(rafMap.size).toBe(1) // still exactly one loop in flight
  })

  it('the returned stopper is instance-scoped — a stale handle will not stop a loop that replaced it', () => {
    const a = fakeScroller()
    const b = fakeScroller()
    let y = 150
    const stopA = startAutoScroll({ getPoint: () => ({ x: 150, y }), scroller: a.el, dragEl: doc, axis: 'y' })
    startAutoScroll({ getPoint: () => ({ x: 150, y }), scroller: b.el, dragEl: doc, axis: 'y' }) // B replaces A
    stopA() // stale handle from A — must be a no-op, not a stop of B
    y = 150
    flush(3)
    y = 299
    flush(20)
    expect(b.scrolls()).toBeGreaterThan(400) // B kept running — stopA didn't touch it
  })

  it('clamps a huge dt so an rAF stall does not teleport the scroll', () => {
    const { el, scrolls } = fakeScroller()
    let y = 150
    startAutoScroll({ getPoint: () => ({ x: 150, y }), scroller: el, dragEl: doc, axis: 'y' })
    flush(3)
    y = 299
    flush(5) // scrolling at steady state
    const beforeStall = scrolls()
    flush(1, 5000) // one frame after a 5-second main-thread stall
    const jump = scrolls() - beforeStall
    // Clamped to MAX_FRAME_MS (50ms): well under 100px. Without the clamp it'd be thousands.
    expect(jump).toBeGreaterThan(0)
    expect(jump).toBeLessThan(100)
  })

  it('fires onScrolled after a frame that actually scrolled', () => {
    const { el } = fakeScroller()
    const onScrolled = vi.fn()
    let y = 150
    startAutoScroll({ getPoint: () => ({ x: 150, y }), scroller: el, dragEl: doc, axis: 'y', onScrolled })
    flush(3)
    y = 299
    flush(40)
    expect(onScrolled).toHaveBeenCalled()
  })
})
