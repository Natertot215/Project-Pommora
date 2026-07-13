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

// The same beak silhouette on a VERTICAL edge — `panePath` with the axes transposed. `ny` is the
// beak centre along the pane's height; `nh` its protrusion depth (in x); `nw` its width (along y).
// The beak hangs off the LEFT edge (body inset to x=nh), pointing left at a trigger on that side;
// `flip` mirrors it horizontally to the RIGHT edge.
function panePathVertical(w: number, h: number, r: number, ny: number, nh: number, nw: number, curve: number, flip: boolean): string {
  const fx = (x: number): number => (flip ? w - x : x)
  const half = nw / 2
  const yT = ny - half
  const yB = ny + half
  const cb = Math.min(half * (0.3 + curve), half)
  const ct = Math.min(half * (0.15 + curve), half * 0.9)
  return [
    `M ${fx(nh)} ${r}`,
    `L ${fx(nh)} ${yT}`,
    `C ${fx(nh)} ${yT + cb} ${fx(0)} ${ny - ct} ${fx(0)} ${ny}`,
    `C ${fx(0)} ${ny + ct} ${fx(nh)} ${yB - cb} ${fx(nh)} ${yB}`,
    `L ${fx(nh)} ${h - r}`,
    `Q ${fx(nh)} ${h} ${fx(nh + r)} ${h}`,
    `L ${fx(w - r)} ${h}`,
    `Q ${fx(w)} ${h} ${fx(w)} ${h - r}`,
    `L ${fx(w)} ${r}`,
    `Q ${fx(w)} 0 ${fx(w - r)} 0`,
    `L ${fx(nh + r)} 0`,
    `Q ${fx(nh)} 0 ${fx(nh)} ${r}`,
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
  notchInsetRight,
  notchInsetBottom,
  notchSide = 'top',
  accentOutline = false,
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
  /** Beak position for a top/bottom notch, measured from the pane's right edge (omit = centered). */
  notchInsetRight?: number
  /** Beak position for a left/right notch, measured from the pane's bottom edge (omit = centered). */
  notchInsetBottom?: number
  /** Which edge the beak hangs off: 'top' (default, downward pane) / 'bottom' (upward) / 'left' /
   *  'right' (sideways panes — the beak points horizontally at the trigger). */
  notchSide?: 'top' | 'bottom' | 'left' | 'right'
  /** Outline the pane in accent @ tint-secondary (the page-location border signal) instead of the
   *  default white frost stroke — opt-in for the block-surface pickers only. */
  accentOutline?: boolean
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
  const vertical = notchSide === 'left' || notchSide === 'right'
  // Clamp the beak clear of the corner radii (along whichever edge it rides) so it can't break the outline.
  const along = vertical ? h : w
  const nMin = radius + notchWidth / 2 + 2
  const nMax = along - radius - notchWidth / 2 - 2
  const nRaw = vertical
    ? notchInsetBottom !== undefined
      ? h - notchInsetBottom
      : h / 2
    : notchInsetRight !== undefined
      ? w - notchInsetRight
      : w / 2
  const n = nMin < nMax ? Math.min(Math.max(nRaw, nMin), nMax) : along / 2
  const flip = notchSide === 'bottom' || notchSide === 'right'
  const d = ready
    ? vertical
      ? panePathVertical(w, h, radius, n, notchHeight, notchWidth, notchCurve, flip)
      : panePath(w, h, radius, n, notchHeight, notchWidth, notchCurve, flip)
    : ''
  // The Bloom starts from the beak tip: the sideways tip sits on the near vertical edge, the
  // up/down tip on the near horizontal edge.
  const origin = vertical ? `${flip ? w : 0}px ${n}px` : `${n}px ${flip ? h : 0}px`

  return (
    // The Bloom class rides the pane + frame INDIVIDUALLY (same keyframes + origin var → one move),
    // never this wrapper: an opacity-animated ancestor becomes the frost's backdrop root and the
    // backdrop-filter silently samples nothing (Build-Gotchas §Glass — the chip-× lesson).
    <div
      ref={popRef}
      className={s.pop}
      style={
        {
          ...(ready ? { '--dropdown-origin': origin, '--notch-h': `${notchHeight}px` } : null),
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
          {/* Default: the white frost stroke. accentOutline (block-surface pickers): accent @ tint-secondary,
              the page-location border signal — set via the CSS `stroke` property, not the SVG attribute, so
              var()/color-mix() resolve (the tokens live on :root/html, which the body portal inherits). */}
          <path
            d={d}
            fill="none"
            strokeWidth={1}
            stroke={accentOutline ? undefined : '#FFFFFF'}
            strokeOpacity={accentOutline ? undefined : PANE_FROST.borderAlpha}
            style={
              accentOutline
                ? { stroke: 'color-mix(in srgb, var(--accent) var(--tint-secondary), transparent)' }
                : undefined
            }
          />
        </svg>
      )}
    </div>
  )
}
