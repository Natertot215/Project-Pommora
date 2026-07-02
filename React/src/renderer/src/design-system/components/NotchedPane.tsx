import { useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react'
import { GlassPane, PANE_FROST } from '../materials'
import { cx } from '../cx'
import * as s from './notchedPane.css'

// The notch is ONE path used both as the frost clip-path and the SVG border stroke — shape + outline
// are the same line. `curve` softens the base corners where the beak meets the top edge.
function panePath(w: number, h: number, r: number, nx: number, nh: number, nw: number, curve: number): string {
  const xL = nx - nw / 2
  const xR = nx + nw / 2
  const bf = Math.min((nw / 2) * curve, nw / 2 - 1) // base-corner blend run
  const sy = nh * (1 - bf / (nw / 2)) // y where the blend rejoins the straight slope
  return [
    `M ${r} ${nh}`,
    `L ${xL - bf} ${nh}`,
    `Q ${xL} ${nh} ${xL + bf} ${sy}`,
    `L ${nx} 0`,
    `L ${xR - bf} ${sy}`,
    `Q ${xR} ${nh} ${xR + bf} ${nh}`,
    `L ${w - r} ${nh}`,
    `Q ${w} ${nh} ${w} ${nh + r}`,
    `L ${w} ${h - r}`,
    `Q ${w} ${h} ${w - r} ${h}`,
    `L ${r} ${h}`,
    `Q 0 ${h} 0 ${h - r}`,
    `L 0 ${nh + r}`,
    `Q 0 ${nh} ${r} ${nh}`,
    'Z'
  ].join(' ')
}

/**
 * The shared beaked-glass dropdown shell (hoisted from PickerMenu): a GlassPane whose frost is
 * clipped to a rounded rect with a top beak, outlined by an SVG stroke of the SAME path (a rect
 * border/box-shadow can't trace the beak — the frame owns outline + shadow). Publishes
 * `--notch-h` so a surface's gutter can clear the beak band, and points `--dropdown-origin` at
 * the beak tip so the Bloom starts from it. `notchInsetRight` aims the beak (measured from the
 * pane's right edge, for right-anchored dropdowns); omitted = centered.
 */
export function NotchedPane({
  children,
  className,
  animationClass,
  solid = false,
  radius = 14,
  notchWidth = 28,
  notchHeight = 8,
  notchCurve = 0.25,
  notchInsetRight,
  style
}: {
  children: ReactNode
  /** The surface's own classes (gutter/layout) — applied to the GlassPane. */
  className?: string
  /** The open/close Bloom class — applied to the measured wrapper so pane + frame animate as one. */
  animationClass?: string
  /** A window-background fill under the frost, reading opaque over any backdrop. */
  solid?: boolean
  radius?: number
  notchWidth?: number
  notchHeight?: number
  notchCurve?: number
  notchInsetRight?: number
  style?: CSSProperties
}): React.JSX.Element {
  const popRef = useRef<HTMLDivElement>(null)
  const [size, setSize] = useState({ w: 0, h: 0 })
  useLayoutEffect(() => {
    const el = popRef.current
    if (!el) return
    const measure = (): void => setSize({ w: el.offsetWidth, h: el.offsetHeight })
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  const { w, h } = size
  const ready = w > 0 && h > 0
  // Clamp the beak clear of the corner radii so an aimed notch can't break the outline.
  const nxMin = radius + notchWidth / 2 + 2
  const nxMax = w - radius - notchWidth / 2 - 2
  const nxRaw = notchInsetRight !== undefined ? w - notchInsetRight : w / 2
  const nx = nxMin < nxMax ? Math.min(Math.max(nxRaw, nxMin), nxMax) : w / 2
  const d = ready ? panePath(w, h, radius, nx, notchHeight, notchWidth, notchCurve) : ''

  return (
    // The Bloom class rides the pane + frame INDIVIDUALLY (same keyframes + origin var → one move),
    // never this wrapper: an opacity-animated ancestor becomes the frost's backdrop root and the
    // backdrop-filter silently samples nothing (Build-Gotchas §Glass — the chip-× lesson).
    <div
      ref={popRef}
      className={s.pop}
      style={
        {
          ...(ready ? { '--dropdown-origin': `${nx}px 0px`, '--notch-h': `${notchHeight}px` } : null),
          ...style
        } as CSSProperties
      }
    >
      <GlassPane
        className={cx(className, animationClass)}
        style={{
          ...(solid ? { background: 'var(--bg-window)' } : null),
          border: 'none',
          boxShadow: 'none',
          ...(d ? { clipPath: `path('${d}')` } : null)
        }}
      >
        {children}
      </GlassPane>
      {d && (
        <svg className={cx(s.frame, animationClass)} width={w} height={h} aria-hidden>
          <path d={d} fill="none" stroke="#FFFFFF" strokeOpacity={PANE_FROST.borderAlpha} strokeWidth={1} />
        </svg>
      )}
    </div>
  )
}
