import type { ReactNode } from 'react'
import { cx } from '../cx'
import { truncateHoverScroll } from '../tokens/typography.css'
import '../edge-fade.css'

/**
 * Slide a hover-scrolled box back to its start when the pointer leaves — scrollLeft isn't a
 * CSS-transitionable property, so a rAF tween honours the panel-slide timing (reads
 * --duration-base, never hardcodes). Hoisted from the sidebar rows: ONE mechanism for every
 * truncate-then-hover-scroll surface.
 */
export function slideScrollBack(scroller: HTMLElement): void {
  const from = scroller.scrollLeft
  if (from <= 0) return
  const raw = getComputedStyle(document.documentElement).getPropertyValue('--duration-base').trim()
  const ms = (raw.endsWith('ms') ? Number.parseFloat(raw) : Number.parseFloat(raw) * 1000) || 240
  const t0 = performance.now()
  const tick = (t: number): void => {
    const p = Math.min(1, (t - t0) / ms)
    scroller.scrollLeft = from * (1 - p) ** 3 // ease-out settle into the start, matching --ease-standard
    if (p < 1) requestAnimationFrame(tick)
  }
  requestAnimationFrame(tick)
}

/**
 * The shared truncate-then-hover-scroll box (the sidebar-row mechanism, componentized): content
 * clips at rest, the pointer scrolls it horizontally in place, leaving slides it back to the
 * start. Overflowing content always ECLIPSES — a fade at whichever edge hides content, never a
 * hard cutoff — via the scroll-driven mask in OverflowScroll.css. The engine activates the fade
 * only while the box genuinely overflows, so there is no JS measurement and no signal to plumb:
 * column resizes, content edits, and zoom changes all re-resolve on their own. Wrap ANY
 * overflowing content — the consumer's class owns display/gap/width; --edge-fade tunes the
 * fade width per context.
 */
export function OverflowScroll({
  children,
  className,
}: {
  children: ReactNode
  className?: string
}): React.JSX.Element {
  return (
    <span
      className={cx(truncateHoverScroll, 'overflow-eclipse', className)}
      onPointerLeave={(e) => slideScrollBack(e.currentTarget)}
    >
      {children}
    </span>
  )
}
