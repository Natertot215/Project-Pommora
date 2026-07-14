// App-wide auto-scroll-on-drag. One singleton rAF loop (below) scrolls a FIXED container — resolved
// once at drag start — toward whichever edge the pointer holds near: frame-synced, proximity-ramped,
// time-dampened, direction-gated, limit-aware. Every drag surface feeds it a point + a scroller; no
// surface re-implements the loop. Tuning lives in autoscroll.css, read off the drag element once per
// drag. The pure math below is unit-tested; the loop's DOM glue is verified live.

export type Axis = 'x' | 'y' | 'xy'

export interface Params {
  edge: number // px band from a container edge where scroll engages
  speed: number // px/second at the true edge
  ramp: number // proximity exponent (2 = quadratic)
  dampenMs: number // time-dampening window from drag start
}

export interface Intent {
  up: boolean
  down: boolean
  left: boolean
  right: boolean
}

/** Does an element scroll in `axis`? Pure predicate over computed overflow + measured dims. */
export function scrollableInAxis(
  overflowX: string,
  overflowY: string,
  dims: { scrollWidth: number; clientWidth: number; scrollHeight: number; clientHeight: number },
  axis: Axis
): boolean {
  const y = (overflowY === 'auto' || overflowY === 'scroll') && dims.scrollHeight > dims.clientHeight
  const x = (overflowX === 'auto' || overflowX === 'scroll') && dims.scrollWidth > dims.clientWidth
  if (axis === 'y') return y
  if (axis === 'x') return x
  return x || y
}

/** Nearest ancestor of `el` that scrolls IN THE NEEDED AXIS (default both), or null. Axis-aware so a
 *  vertical drag skips an x-only ancestor (e.g. the table's `overflow-x` shell) to reach the real y-scroller. */
export function findScroller(el: HTMLElement | null, axis: Axis = 'xy'): HTMLElement | null {
  let n = el?.parentElement ?? null
  while (n) {
    const s = getComputedStyle(n)
    if (scrollableInAxis(s.overflowX, s.overflowY, n, axis)) return n
    n = n.parentElement
  }
  return null
}

/** Desired scroll velocity (px/sec, signed) for one axis: negative toward `lo`, positive toward `hi`,
 *  0 outside the edge band. A point past the edge (depth > edge) reads as max ramp — no viewport clamp
 *  needed. Pre-dampening, pre-limit. */
export function edgeVelocity(lo: number, hi: number, p: number, { edge, speed, ramp }: Params): number {
  const ramped = (depth: number): number => speed * Math.min(1, depth / edge) ** ramp
  if (p < lo + edge) return -ramped(lo + edge - p)
  if (p > hi - edge) return ramped(p - (hi - edge))
  return 0
}

/** Time-dampening factor 0→1 over the first `dampenMs` of a drag. */
export function dampen(elapsedMs: number, dampenMs: number): number {
  return dampenMs <= 0 ? 1 : Math.min(1, elapsedMs / dampenMs)
}

/** Zero a velocity that would push past a scroll limit — no render churn while pinned at a maxed edge. */
export function clampToLimit(v: number, pos: number, max: number): number {
  if (v < 0 && pos <= 0) return 0
  if (v > 0 && pos >= max) return 0
  return v
}

/** Sub-pixel step: fold the fractional remainder forward so slow ramps don't round to 0. Returns the
 *  integer pixels to scroll this frame and the carried remainder. */
export function stepPixels(v: number, dtMs: number, frac: number): { px: number; frac: number } {
  const raw = v * (dtMs / 1000) + frac
  const px = Math.trunc(raw)
  return { px, frac: raw - px }
}

/** Direction-intent gate. A direction may scroll only after the pointer has been OUTSIDE that
 *  direction's edge band at least once since drag start — so grabbing an item already pinned at the
 *  bottom edge doesn't immediately rocket the container. Being outside a band (velocity not pushing
 *  that way) arms it. Mutates + reads `intent`. */
export function gateIntent(intent: Intent, vx: number, vy: number): { vx: number; vy: number } {
  if (vy >= 0) intent.up = true
  if (vy <= 0) intent.down = true
  if (vx >= 0) intent.left = true
  if (vx <= 0) intent.right = true
  return {
    vx: (vx < 0 && !intent.left) || (vx > 0 && !intent.right) ? 0 : vx,
    vy: (vy < 0 && !intent.up) || (vy > 0 && !intent.down) ? 0 : vy
  }
}

// TEMPORARY back-compat shim during the auto-scroll migration. Reproduces the OLD px/frame behavior
// (speed 14, no dampen) so the not-yet-migrated inline callers (engine/SurfaceView/paneDnd) compile
// and behave identically until each moves onto the loop. Deleted once the last caller migrates.
export function autoScroll(scroller: HTMLElement, x: number, y: number): boolean {
  const r = scroller.getBoundingClientRect()
  const p: Params = { edge: 48, speed: 14, ramp: 2, dampenMs: 0 }
  const sx = clampToLimit(edgeVelocity(r.left, r.right, x, p), scroller.scrollLeft, scroller.scrollWidth - scroller.clientWidth)
  const sy = clampToLimit(edgeVelocity(r.top, r.bottom, y, p), scroller.scrollTop, scroller.scrollHeight - scroller.clientHeight)
  if (!sx && !sy) return false
  scroller.scrollBy(sx, sy)
  return true
}
