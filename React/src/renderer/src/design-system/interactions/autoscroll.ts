// Auto-scroll for the drag engine. dnd-kit drives this off a 5ms setInterval with a linear ramp; we use
// the engine's rAF loop with an ease-in ramp (gentler entry, frame-synced — no double-steps). Kept
// deliberately small: nearest scrollable ancestor only, both axes.

const EDGE = 48 // px from a container edge where auto-scroll engages
const MAX = 14 // px/frame at the very edge

/** Nearest scrollable ancestor of `el` (overflow auto/scroll with actual overflow), or null. */
export function findScroller(el: HTMLElement | null): HTMLElement | null {
  let n = el?.parentElement ?? null
  while (n) {
    const s = getComputedStyle(n)
    const scrollableY = (s.overflowY === 'auto' || s.overflowY === 'scroll') && n.scrollHeight > n.clientHeight
    const scrollableX = (s.overflowX === 'auto' || s.overflowX === 'scroll') && n.scrollWidth > n.clientWidth
    if (scrollableY || scrollableX) return n
    n = n.parentElement
  }
  return null
}

/** If the pointer is within EDGE of a container edge, scroll toward it (ease-in by proximity).
 *  Returns true if it scrolled this frame. */
export function autoScroll(scroller: HTMLElement, x: number, y: number): boolean {
  const r = scroller.getBoundingClientRect()
  const ramp = (p: number): number => MAX * Math.min(1, p) ** 2
  let sx = 0
  let sy = 0
  if (y < r.top + EDGE) sy = -ramp((r.top + EDGE - y) / EDGE)
  else if (y > r.bottom - EDGE) sy = ramp((y - (r.bottom - EDGE)) / EDGE)
  if (x < r.left + EDGE) sx = -ramp((r.left + EDGE - x) / EDGE)
  else if (x > r.right - EDGE) sx = ramp((x - (r.right - EDGE)) / EDGE)
  // Zero out a direction already at its scroll limit — a no-op scrollBy would still report "scrolled"
  // and churn a render every frame while pinned against a maxed-out edge.
  if (sy < 0 && scroller.scrollTop <= 0) sy = 0
  else if (sy > 0 && scroller.scrollTop >= scroller.scrollHeight - scroller.clientHeight) sy = 0
  if (sx < 0 && scroller.scrollLeft <= 0) sx = 0
  else if (sx > 0 && scroller.scrollLeft >= scroller.scrollWidth - scroller.clientWidth) sx = 0
  if (!sx && !sy) return false
  scroller.scrollBy(sx, sy)
  return true
}
