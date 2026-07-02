import { useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react'
import { GlassPane, PANE_FROST } from '../../materials'
import { dropdownOpen, dropdownClose } from '../../animations.css'
import { cx } from '../../cx'
import * as s from './pickerMenu.css'

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

// Uses the `dropdown` token (snappier, symmetric Bloom — same keyframes as the menu Bloom, shared with
// AutocompletePanel). `--dropdown-origin` points at the notch tip so the bloom starts from the beak.
export function PickerMenu({
  children,
  closing = false,
  solid = false,
  radius = 14,
  notchWidth = 28,
  notchHeight = 8,
  notchCurve = 0.25,
  style
}: {
  children: ReactNode
  closing?: boolean
  /** The Solid variation: a window-background fill under the frost, reading opaque over any
   *  backdrop (the table's value picker). Default stays pure glass. */
  solid?: boolean
  radius?: number
  notchWidth?: number
  notchHeight?: number
  notchCurve?: number
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
  const d = ready ? panePath(w, h, radius, w / 2, notchHeight, notchWidth, notchCurve) : ''

  return (
    <div className={s.anchor}>
      <div
        ref={popRef}
        className={cx(s.pop, closing ? dropdownClose : dropdownOpen)}
        style={{ ...(ready ? { '--dropdown-origin': `${w / 2}px 0px` } : null), ...style } as CSSProperties}
      >
        <GlassPane
          className={s.surface}
          style={{
            // GlassPane's frost is the surface; its rect border/shadow can't trace the beak, so the
            // frame SVG draws the outline + shadow. Clip the frost to the notch path once measured.
            ...(solid ? { background: 'var(--bg-window)' } : null),
            border: 'none',
            boxShadow: 'none',
            ...(d ? { clipPath: `path('${d}')` } : null),
            paddingTop: notchHeight + 6
          }}
        >
          {children}
        </GlassPane>
        {d && (
          <svg className={s.frame} width={w} height={h} aria-hidden>
            <path d={d} fill="none" stroke="#FFFFFF" strokeOpacity={PANE_FROST.borderAlpha} strokeWidth={1} />
          </svg>
        )}
      </div>
    </div>
  )
}

// Chip overflow (truncate + scroll) is handled by `chipLabel` in design-system/tokens — no overflow
// logic needed here.
export function PickerOption({
  children,
  onClick,
  selected = false
}: {
  children: ReactNode
  onClick?: () => void
  selected?: boolean
}): React.JSX.Element {
  return (
    <button type="button" className={cx(s.option, selected && s.optionSelected)} onClick={onClick}>
      {children}
    </button>
  )
}
