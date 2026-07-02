import type { CSSProperties, ReactNode } from 'react'
import { useEffect, useRef, useState } from 'react'
import { cx } from '../cx'
import { truncateHoverScroll } from '../tokens/typography.css'

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
 * start. Overflowing content always ECLIPSES — a fade at whichever edge hides more content,
 * never a hard cutoff — via one two-sided mask (the token's hover mask handles only the left).
 * Wrap ANY overflowing content — a title with its inline icon, a chip row, a formatted date —
 * the mechanism doesn't care what's inside; the consumer's class owns display/gap/width.
 */
export function OverflowScroll({
  children,
  className,
  fade = 16
}: {
  children: ReactNode
  className?: string
  fade?: number
}): React.JSX.Element {
  const ref = useRef<HTMLSpanElement>(null)
  const [edges, setEdges] = useState({ left: false, right: false })

  const measure = (): void => {
    const el = ref.current
    if (!el) return
    const left = el.scrollLeft > 0
    const right = el.scrollLeft + el.clientWidth < el.scrollWidth - 1
    setEdges((prev) => (prev.left === left && prev.right === right ? prev : { left, right }))
  }
  // Content/box changes re-measure through the observer; scrolling re-measures inline below.
  useEffect(() => {
    measure()
    const el = ref.current
    if (!el) return
    const ro = new ResizeObserver(measure)
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  const mask =
    edges.left || edges.right
      ? `linear-gradient(to right, transparent 0, #000000 ${edges.left ? fade : 0}px, #000000 calc(100% - ${edges.right ? fade : 0}px), transparent 100%)`
      : undefined
  return (
    <span
      ref={ref}
      className={cx(truncateHoverScroll, className)}
      style={
        mask
          ? ({ maskImage: mask, WebkitMaskImage: mask, textOverflow: 'clip', '--scroll-fade': '0px' } as CSSProperties)
          : undefined
      }
      onScroll={measure}
      onPointerLeave={(e) => slideScrollBack(e.currentTarget)}
    >
      {children}
    </span>
  )
}
