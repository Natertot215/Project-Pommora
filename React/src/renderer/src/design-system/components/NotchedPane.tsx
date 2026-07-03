import { useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react'
import { GlassPane, PANE_FROST } from '../materials'
import { cx } from '../cx'
import * as s from './notchedPane.css'

// The notch is ONE path used both as the frost clip-path and the SVG border stroke — shape + outline
// are the same line. The beak is the Apple-popover silhouette: one cubic per side, tangent to the
// top edge at its base and horizontal over the apex — a smooth fillet into a rounded crest, no
// straight slopes, no tip vertex. `curve` morphs sharp↔round (it scales both tangent runs; the
// 0.25 default lands on Apple's proportions). `flip` mirrors the whole outline vertically for
// upward-opening panes — the beak then hangs from the BOTTOM edge, pointing down at the trigger.
function panePath(w: number, h: number, r: number, nx: number, nh: number, nw: number, curve: number, flip: boolean): string {
  const fy = (y: number): number => (flip ? h - y : y)
  const half = nw / 2
  const xL = nx - half
  const xR = nx + half
  const cb = Math.min(half * (0.3 + curve), half) // base tangent run (fillet width)
  const ct = Math.min(half * (0.15 + curve), half * 0.9) // apex tangent run (crest roundness)
  return [
    `M ${r} ${fy(nh)}`,
    `L ${xL} ${fy(nh)}`,
    `C ${xL + cb} ${fy(nh)} ${nx - ct} ${fy(0)} ${nx} ${fy(0)}`,
    `C ${nx + ct} ${fy(0)} ${xR - cb} ${fy(nh)} ${xR} ${fy(nh)}`,
    `L ${w - r} ${fy(nh)}`,
    `Q ${w} ${fy(nh)} ${w} ${fy(nh + r)}`,
    `L ${w} ${fy(h - r)}`,
    `Q ${w} ${fy(h)} ${w - r} ${fy(h)}`,
    `L ${r} ${fy(h)}`,
    `Q 0 ${fy(h)} 0 ${fy(h - r)}`,
    `L 0 ${fy(nh + r)}`,
    `Q 0 ${fy(nh)} ${r} ${fy(nh)}`,
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
  notchWidth = 34,
  notchHeight = 8,
  notchCurve = 0.25,
  notchInsetLeft,
  notchInsetRight,
  notchSide = 'top',
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
  /** Beak aim from the pane's LEFT edge — for left-anchored dropdowns; wins over insetRight. */
  notchInsetLeft?: number
  notchInsetRight?: number
  /** 'bottom' mirrors the outline for upward-opening panes — beak points DOWN at the trigger. */
  notchSide?: 'top' | 'bottom'
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
  const nxRaw = notchInsetLeft !== undefined ? notchInsetLeft : notchInsetRight !== undefined ? w - notchInsetRight : w / 2
  const nx = nxMin < nxMax ? Math.min(Math.max(nxRaw, nxMin), nxMax) : w / 2
  const flip = notchSide === 'bottom'
  const d = ready ? panePath(w, h, radius, nx, notchHeight, notchWidth, notchCurve, flip) : ''

  return (
    // The Bloom class rides the pane + frame INDIVIDUALLY (same keyframes + origin var → one move),
    // never this wrapper: an opacity-animated ancestor becomes the frost's backdrop root and the
    // backdrop-filter silently samples nothing (Build-Gotchas §Glass — the chip-× lesson).
    <div
      ref={popRef}
      className={s.pop}
      style={
        {
          ...(ready ? { '--dropdown-origin': `${nx}px ${flip ? `${h}px` : '0px'}`, '--notch-h': `${notchHeight}px` } : null),
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
