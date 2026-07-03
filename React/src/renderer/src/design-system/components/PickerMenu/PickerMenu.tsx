import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode, type RefObject } from 'react'
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
  triggerRef,
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
  /** The element the picker hangs off — measured for placement + exempted from dismiss (so a toggle
   *  trigger can't dismiss-then-reopen). Falls back to the marker's parent when omitted. */
  triggerRef?: RefObject<HTMLElement | null>
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
  const [pos, setPos] = useState<{ top: number; right: number; notchInset: number } | null>(null)

  // The pane hangs off the trigger's right edge and opens down-left (a stable dropdown — the pane
  // doesn't move to center the beak). The beak lands as far right as the corner radius allows
  // (`reserve` = the notch's clamp), so we push the pane's right edge `reserve` past the trigger
  // center — then that clamp-limited beak sits exactly on the trigger. Re-runs on scroll/resize.
  const reserve = radius + notchWidth / 2 + 2
  useLayoutEffect(() => {
    if (!selfManaged || !mounted) return
    const trigger = triggerRef?.current ?? markerRef.current?.parentElement
    if (!trigger) return
    const measure = (): void => {
      const t = trigger.getBoundingClientRect()
      const center = t.left + t.width / 2
      const right = Math.max(VIEWPORT_MARGIN, window.innerWidth - center - reserve)
      setPos({ top: t.bottom + GAP, right, notchInset: reserve })
    }
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(trigger)
    window.addEventListener('scroll', measure, true)
    window.addEventListener('resize', measure)
    return () => {
      ro.disconnect()
      window.removeEventListener('scroll', measure, true)
      window.removeEventListener('resize', measure)
    }
  }, [selfManaged, mounted, reserve, triggerRef])

  // Outside clicks dismiss via the backdrop below the pane (rendered in the portal). Escape is handled
  // here since the backdrop only catches pointers.
  useEffect(() => {
    if (!selfManaged || !onDismiss || open !== true || closing) return
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === 'Escape') onDismiss()
    }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
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

  // Closed (and past its exit) — render nothing, so no stray backdrop/pane sits over the page
  // swallowing hover/clicks. The marker only needs to exist while a placement is being measured.
  if (!mounted) return null

  // Self-managed — a fixed top layer (body portal) escaping any clipping ancestor, beak aimed
  // dynamically. The pane mounts hidden so it can be measured, then reveals at its computed spot.
  return (
    <>
      <span ref={markerRef} aria-hidden style={{ display: 'none' }} />
      {createPortal(
        <>
          {onDismiss && !closing ? <div className={s.backdrop} onClick={onDismiss} /> : null}
          <div
            ref={paneRef}
            className={s.layer}
            style={{
              top: pos ? `${pos.top}px` : '0',
              right: pos ? `${pos.right}px` : '0',
              visibility: pos ? undefined : 'hidden',
              pointerEvents: closing ? 'none' : undefined
            }}
          >
            {pane}
          </div>
        </>,
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
