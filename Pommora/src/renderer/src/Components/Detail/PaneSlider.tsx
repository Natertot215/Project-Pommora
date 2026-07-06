import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react'
import { cx } from '../../design-system/cx'
import * as s from './paneSlider.css'

/**
 * Two-slot horizontal nav with animated height — the one slide primitive every pane rides, so no
 * surface hand-rolls its own push/back state. Declare `open` (root ↔ detail) and it does the rest: on
 * push it slides the detail in from the right and animates the viewport height to it; back reverses.
 * Width, height, and the slide share one duration/easing so the horizontal move and the vertical
 * resize land together.
 *
 * The measure-then-flip is intrinsic (D-1): both slots stay mounted (each watched by a ResizeObserver)
 * and the push lags the flip by one frame, so the detail's height is already measured the instant the
 * viewport animates — no growing-from-`auto` entry bounce. Back flips immediately so the slide-out
 * isn't delayed. Nesting composes: a detail may itself be a PaneSlider (each only slides + resizes, so
 * the inner height change just feeds the outer's ResizeObserver).
 *
 * The slider ONLY slides + resizes — it never caps or scrolls a slot. A slot that needs a ceiling or a
 * pinned footer wraps its content in a `MenuScrollFrame` (the single cap/scroll/footer source); the
 * slider just animates to the frame's already-capped height. This keeps the two mechanisms from
 * fighting (a slot scrolling AND a frame body scrolling was the double-container that broke the slide).
 */
export function PaneSlider({
  open,
  root,
  detail,
  minWidth,
  minHeight
}: {
  /** false → show root (slot A); true → slide to the detail (slot B). Owns the two-phase entry. */
  open: boolean
  root: ReactNode
  detail: ReactNode
  /** Width floor (px) per slot, so a sparse pane keeps the dropdown's minimum width (no shrink-wrap). */
  minWidth?: number
  /** Height floor (px) per slot, so a sparse pane reserves height and its footer pins to the bottom. */
  minHeight?: number
}): React.JSX.Element {
  const aRef = useRef<HTMLDivElement>(null)
  const bRef = useRef<HTMLDivElement>(null)
  const [size, setSize] = useState({ aw: 0, ah: 0, bw: 0, bh: 0 })
  const [enabled, setEnabled] = useState(false)
  // The measure-then-flip: the detail mounts (slot B) the same render `open` turns true, so a frame
  // later the ResizeObserver has its height and the viewport animates to a known target instead of
  // snapping from `auto`. Back (open→false) flips immediately so the slide-out isn't held a frame.
  const [active, setActive] = useState<'a' | 'b'>('a')
  useEffect(() => {
    if (!open) {
      setActive('a')
      return
    }
    const raf = requestAnimationFrame(() => setActive('b'))
    return () => cancelAnimationFrame(raf)
  }, [open])

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
  // The active slot's height (a MenuScrollFrame has already capped it) — the viewport animates to it.
  const height = active === 'a' ? size.ah : size.bh
  // Slide left by slot A's width to bring B flush against the viewport's left edge.
  const shift = active === 'b' ? size.aw : 0
  return (
    <div
      className={cx(s.viewport, enabled && s.viewportAnimated)}
      style={{ width: width || undefined, height: height || undefined }}
    >
      <div className={cx(s.track, enabled && s.trackAnimated)} style={{ transform: `translateX(-${shift}px)` }}>
        <div className={s.slot} inert={active === 'b'}>
          <div ref={aRef} className={s.slotContent} style={{ minWidth, minHeight }}>
            {root}
          </div>
        </div>
        <div className={s.slot} inert={active === 'a'}>
          <div ref={bRef} className={s.slotContent} style={{ minWidth, minHeight }}>
            {detail}
          </div>
        </div>
      </div>
    </div>
  )
}
