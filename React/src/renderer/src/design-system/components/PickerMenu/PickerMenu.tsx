import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { dropdownOpen, dropdownClose } from '../../animations.css'
import { useExitPresence } from '../../useExitPresence'
import { NotchedPane } from '../NotchedPane'
import { cx } from '../../cx'
import * as s from './pickerMenu.css'

const GAP = 6 // trigger → pane
const VIEWPORT_MARGIN = 8 // keep the pane this far from the viewport edges

// Uses the `dropdown` token (snappier, symmetric Bloom — same keyframes as the menu Bloom, shared with
// AutocompletePanel). The beaked shell is the shared NotchedPane; this stays the picker-flavoured skin.
//
// Two lifecycle modes:
//  • Self-managed (pass `open` + `onDismiss`): PickerMenu owns mount → Bloom-out → unmount via
//    useExitPresence, and renders on a fixed TOP LAYER (a body portal) so it escapes any clipping
//    ancestor — positioned at the trigger, beak aimed at it dynamically, dismissed on an outside
//    click/Escape (the trigger itself is exempt, so its toggle doesn't re-open). The one-liner most
//    pickers want.
//  • Manual (pass `closing`, mount the element yourself): inline, caller-driven — for the few
//    consumers with bespoke close logic (a multi-select picker that stays open on pick).
export function PickerMenu({
  children,
  open,
  onDismiss,
  closing: closingProp = false,
  solid = false,
  radius = 14,
  notchWidth = 28,
  notchHeight = 8,
  notchCurve = 0.225,
  direction = 'down',
  align = 'center',
  style
}: {
  children: ReactNode
  /** Self-managed mode: PickerMenu mounts/exits + portals + dismisses off this. Omit for manual mode. */
  open?: boolean
  /** Self-managed dismissal target (outside-click / Escape). */
  onDismiss?: () => void
  /** Manual mode: the caller's exit flag, ridden to the Bloom-out. Ignored when `open` is set. */
  closing?: boolean
  /** The Solid variation: a window-background fill under the frost, reading opaque over any backdrop. */
  solid?: boolean
  radius?: number
  notchWidth?: number
  notchHeight?: number
  notchCurve?: number
  /** 'up' hangs the pane ABOVE its trigger with the beak pointing down (bottom-of-pane hosts). */
  direction?: 'down' | 'up'
  /** Horizontal anchor: 'center' over the trigger, or 'end' with the pane's right edge on it. */
  align?: 'center' | 'end'
  style?: CSSProperties
}): React.JSX.Element | null {
  const selfManaged = open !== undefined
  const { mounted, closing: exitClosing } = useExitPresence(open ?? true)
  const closing = selfManaged ? exitClosing : closingProp
  const paneRef = useRef<HTMLDivElement>(null)
  const markerRef = useRef<HTMLSpanElement>(null)
  const [pos, setPos] = useState<{ top: number; left: number; notchInset: number } | null>(null)

  // Position on the top layer: centered under the trigger, clamped into the viewport, with the beak
  // aimed back at the trigger's center from wherever the pane lands. Measures BOTH the trigger (the
  // marker's parent) and the pane, re-running on scroll/resize.
  useLayoutEffect(() => {
    if (!selfManaged || !mounted) return
    const trigger = markerRef.current?.parentElement
    const pane = paneRef.current
    if (!trigger || !pane) return
    const measure = (): void => {
      const t = trigger.getBoundingClientRect()
      const w = pane.offsetWidth
      const center = t.left + t.width / 2
      const left = Math.max(VIEWPORT_MARGIN, Math.min(center - w / 2, window.innerWidth - w - VIEWPORT_MARGIN))
      setPos({ top: t.bottom + GAP, left, notchInset: left + w - center })
    }
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(trigger)
    ro.observe(pane)
    window.addEventListener('scroll', measure, true)
    window.addEventListener('resize', measure)
    return () => {
      ro.disconnect()
      window.removeEventListener('scroll', measure, true)
      window.removeEventListener('resize', measure)
    }
  }, [selfManaged, mounted])

  // Dismiss on an outside pointerdown / Escape — the pane AND the trigger are exempt, so clicking the
  // toggle trigger closes via its own handler instead of dismiss-then-reopen.
  useEffect(() => {
    if (!selfManaged || !onDismiss || open !== true || closing) return
    const onDown = (e: PointerEvent): void => {
      const target = e.target as Node
      const trigger = markerRef.current?.parentElement
      if (paneRef.current?.contains(target) || trigger?.contains(target)) return
      onDismiss()
    }
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === 'Escape') onDismiss()
    }
    document.addEventListener('pointerdown', onDown, true)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('pointerdown', onDown, true)
      document.removeEventListener('keydown', onKey)
    }
  }, [selfManaged, onDismiss, open, closing])

  const up = direction === 'up'
  const pane = (
    <NotchedPane
      className={cx(s.surface, up && s.surfaceUp)}
      animationClass={closing ? dropdownClose : dropdownOpen}
      solid={solid}
      radius={radius}
      notchWidth={notchWidth}
      notchHeight={notchHeight}
      notchCurve={notchCurve}
      notchInsetRight={pos?.notchInset}
      notchSide={up ? 'bottom' : 'top'}
      style={style}
    >
      {children}
    </NotchedPane>
  )

  // Manual (legacy) — inline, caller-mounted, centered beak.
  if (!selfManaged) {
    return <div className={up ? s.anchorUp : align === 'end' ? s.anchorEnd : s.anchor}>{pane}</div>
  }

  // Self-managed — a fixed top layer (body portal) escaping any clipping ancestor, beak aimed
  // dynamically. The pane mounts hidden so it can be measured, then reveals at its computed spot.
  return (
    <>
      <span ref={markerRef} aria-hidden style={{ display: 'none' }} />
      {createPortal(
        <div
          ref={paneRef}
          className={s.layer}
          style={{
            top: pos ? `${pos.top}px` : '0',
            left: pos ? `${pos.left}px` : '0',
            visibility: pos ? undefined : 'hidden',
            pointerEvents: closing ? 'none' : undefined
          }}
        >
          {pane}
        </div>,
        document.body
      )}
    </>
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
