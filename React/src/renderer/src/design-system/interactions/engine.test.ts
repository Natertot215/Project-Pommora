import { describe, it, expect, vi } from 'vitest'
import { reflow, type Box } from './engine'
import { autoScroll } from './autoscroll'
import { keyboardNext, ARROW_DIRS } from './keyboard'

// A column of uniform 10px-tall slots at y = 0,10,20,...
const column = (n: number): Box[] =>
  Array.from({ length: n }, (_, i) => ({ left: 0, top: i * 10, width: 100, height: 10, cx: 50, cy: i * 10 + 5 }))

// A `cols`-wide grid of 100px cells.
const grid = (count: number, cols: number): Box[] =>
  Array.from({ length: count }, (_, i) => {
    const c = i % cols
    const r = Math.floor(i / cols)
    return { left: c * 100, top: r * 100, width: 100, height: 100, cx: c * 100 + 50, cy: r * 100 + 50 }
  })

describe('reflow — the displacement core', () => {
  // Dragging item 0 down to slot 2: items 1,2 shift up one slot, item 3 stays, active lands on slot 2.
  it('shifts the passed-over items up when dragging forward', () => {
    const r = column(4)
    expect(reflow(r, 2, 0, 1).top).toBe(0) // item 1 → slot 0
    expect(reflow(r, 2, 0, 2).top).toBe(10) // item 2 → slot 1
    expect(reflow(r, 2, 0, 3).top).toBe(30) // item 3 → unchanged
  })

  // Dragging item 3 up to slot 1: items 1,2 shift down one slot, item 0 stays.
  it('shifts the passed-over items down when dragging backward', () => {
    const r = column(4)
    expect(reflow(r, 1, 3, 0).top).toBe(0) // item 0 → unchanged
    expect(reflow(r, 1, 3, 1).top).toBe(20) // item 1 → slot 2
    expect(reflow(r, 1, 3, 2).top).toBe(30) // item 2 → slot 3
  })

  it('is a no-op when over === active (hovering its own slot)', () => {
    const r = column(4)
    for (let i = 0; i < 4; i++) expect(reflow(r, 1, 1, i).top).toBe(i * 10)
  })
})

describe('autoScroll — edge ramp + limit awareness', () => {
  const scroller = (over: Partial<Record<string, number>> = {}) => {
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

  it('does not scroll when the pointer is away from any edge', () => {
    const { el, scrollBy } = scroller()
    expect(autoScroll(el, 100, 200)).toBe(false)
    expect(scrollBy).not.toHaveBeenCalled()
  })

  it('scrolls down (positive) when the pointer nears the bottom edge', () => {
    const { el, scrollBy } = scroller()
    expect(autoScroll(el, 100, 295)).toBe(true)
    expect(scrollBy).toHaveBeenCalledTimes(1)
    expect(scrollBy.mock.calls[0][1]).toBeGreaterThan(0) // sy > 0
  })

  it('scrolls up (negative) when the pointer nears the top edge', () => {
    const { el, scrollBy } = scroller()
    expect(autoScroll(el, 100, 105)).toBe(true)
    expect(scrollBy.mock.calls[0][1]).toBeLessThan(0) // sy < 0
  })

  it('does NOT scroll past the bottom limit (no render churn while pinned)', () => {
    const { el, scrollBy } = scroller({ scrollTop: 800 }) // 800 === scrollHeight(1000) - clientHeight(200)
    expect(autoScroll(el, 100, 295)).toBe(false)
    expect(scrollBy).not.toHaveBeenCalled()
  })

  it('does NOT scroll past the top limit', () => {
    const { el, scrollBy } = scroller({ scrollTop: 0 })
    expect(autoScroll(el, 100, 105)).toBe(false)
    expect(scrollBy).not.toHaveBeenCalled()
  })

  it('ramps faster the closer the pointer is to the edge', () => {
    const near = scroller()
    const far = scroller()
    autoScroll(near.el, 100, 299) // 1px from bottom
    autoScroll(far.el, 100, 260) // ~40px from bottom (just inside EDGE=48)
    expect(Math.abs(near.scrollBy.mock.calls[0][1])).toBeGreaterThan(Math.abs(far.scrollBy.mock.calls[0][1]))
  })
})

describe('keyboardNext — arrow navigation', () => {
  it('steps a vertical list down/up by one slot', () => {
    const r = column(5)
    expect(keyboardNext(r, 0, ARROW_DIRS.ArrowDown)).toBe(1)
    expect(keyboardNext(r, 2, ARROW_DIRS.ArrowUp)).toBe(1)
  })

  it('returns the same index when nothing lies ahead', () => {
    const r = column(5)
    expect(keyboardNext(r, 4, ARROW_DIRS.ArrowDown)).toBe(4) // last row, nothing below
    expect(keyboardNext(r, 0, ARROW_DIRS.ArrowUp)).toBe(0) // first row, nothing above
    expect(keyboardNext(r, 0, ARROW_DIRS.ArrowLeft)).toBe(0) // a column has nothing to the side
  })

  it('navigates a grid by row and column', () => {
    const g = grid(9, 3) // 3x3
    expect(keyboardNext(g, 0, ARROW_DIRS.ArrowRight)).toBe(1) // 0 → 1
    expect(keyboardNext(g, 0, ARROW_DIRS.ArrowDown)).toBe(3) // 0 → directly below
    expect(keyboardNext(g, 4, ARROW_DIRS.ArrowUp)).toBe(1) // centre → directly above
    expect(keyboardNext(g, 4, ARROW_DIRS.ArrowLeft)).toBe(3) // centre → left neighbour
    expect(keyboardNext(g, 4, ARROW_DIRS.ArrowRight)).toBe(5) // centre → right neighbour
  })
})
