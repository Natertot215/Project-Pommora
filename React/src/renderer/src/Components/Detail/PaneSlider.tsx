import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react'
import { cx } from '../../design-system/cx'
import * as s from './paneSlider.css'

/**
 * Two-slot horizontal nav with animated height. Pushing slides the detail (b) in from the right; back
 * reverses — and the viewport height animates to the active slot on the SAME duration/easing as the
 * slide, so the horizontal move and the vertical resize land together. Both slots stay mounted (each
 * watched by a ResizeObserver) so the target height is already known the instant `active` flips.
 */
export function PaneSlider({
  active,
  slotA,
  slotB,
  minWidth,
  minHeight,
  maxHeight
}: {
  active: 'a' | 'b'
  slotA: ReactNode
  slotB: ReactNode
  /** Width floor (px) per slot, so a sparse pane keeps the dropdown's minimum width (no shrink-wrap). */
  minWidth?: number
  /** Height floor (px) per slot, so a sparse pane reserves height and its footer pins to the bottom. */
  minHeight?: number
  /** Height cap (px) — past it a slot scrolls internally under the shared edge fade (A-6). */
  maxHeight?: number
}): React.JSX.Element {
  const aRef = useRef<HTMLDivElement>(null)
  const bRef = useRef<HTMLDivElement>(null)
  const [size, setSize] = useState({ aw: 0, ah: 0, bw: 0, bh: 0 })
  const [enabled, setEnabled] = useState(false)

  useLayoutEffect(() => {
    const a = aRef.current
    const b = bRef.current
    if (!a || !b) return
    const measure = (): void =>
      setSize({ aw: a.offsetWidth, ah: a.offsetHeight, bw: b.offsetWidth, bh: b.offsetHeight })
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(a)
    ro.observe(b)
    return () => ro.disconnect()
  }, [])

  // Arm the transitions only after the first paint, so the pane snaps to its measured size on open
  // instead of growing from 0 / sliding from an arbitrary start.
  useEffect(() => setEnabled(true), [])

  const width = active === 'a' ? size.aw : size.bw
  const measured = active === 'a' ? size.ah : size.bh
  const height = maxHeight ? Math.min(measured, maxHeight) : measured
  // Slide left by slot A's width to bring B flush against the viewport's left edge.
  const shift = active === 'b' ? size.aw : 0
  // The floors ride the MEASURED content div, never the scroll-capped slot box — a floor on the
  // capped box would be invisible to the ResizeObserver and clip a sparse pane.
  const slotClass = cx(s.slot, maxHeight != null && s.slotScrollable, maxHeight != null && 'scroll-edge-fade')
  const slotStyle = maxHeight != null ? { maxHeight } : undefined
  return (
    <div
      className={cx(s.viewport, enabled && s.viewportAnimated)}
      style={{ width: width || undefined, height: height || undefined }}
    >
      <div className={cx(s.track, enabled && s.trackAnimated)} style={{ transform: `translateX(-${shift}px)` }}>
        <div className={slotClass} style={slotStyle} inert={active === 'b'}>
          <div ref={aRef} className={s.slotContent} style={{ minWidth, minHeight }}>
            {slotA}
          </div>
        </div>
        <div className={slotClass} style={slotStyle} inert={active === 'a'}>
          <div ref={bRef} className={s.slotContent} style={{ minWidth, minHeight }}>
            {slotB}
          </div>
        </div>
      </div>
    </div>
  )
}
