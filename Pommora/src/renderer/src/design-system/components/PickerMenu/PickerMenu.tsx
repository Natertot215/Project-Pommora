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
//    ancestor — positioned at the trigger, beak aimed at it dynamically. A full-viewport backdrop
//    under the pane catches the outside click (and covers the trigger, so a toggle can't
//    dismiss-then-reopen); Escape closes too. Both layers carry `data-picker-portal` so a host's
//    useDismiss spares them (its containment check can't see through the portal). The one-liner
//    most pickers want.
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
  center = false,
  bareSurface = false,
  accentOutline = false,
  contentClassName,
  style
}: {
  children: ReactNode
  /** Self-managed mode: PickerMenu mounts/exits + portals + dismisses off this. Omit for manual mode. */
  open?: boolean
  /** Self-managed dismissal target (outside-click / Escape). */
  onDismiss?: () => void
  /** The element the picker hangs off — measured for placement (any `Element`: an icon glyph is an
   *  SVG). Falls back to the marker's parent when omitted. (Dismiss is handled by the backdrop.) */
  triggerRef?: RefObject<Element | null>
  /** Manual mode: the caller's exit flag, ridden to the Bloom-out. Ignored when `open` is set. */
  closing?: boolean
  /** The Solid variation: a window-background fill under the frost, reading opaque over any backdrop. */
  solid?: boolean
  radius?: number
  notchWidth?: number
  notchHeight?: number
  notchCurve?: number
  /** 'up' hangs the pane ABOVE its trigger with the beak pointing down (bottom-of-pane hosts). */
  direction?: 'down' | 'up' | 'left' | 'right'
  /** Centred mode — the pane straddles the trigger centre with a centred beak (the TextPicker rename
   *  field), instead of the default right-anchored dropdown. */
  center?: boolean
  /** Drop the default surface gutter entirely — `contentClassName` is the ONLY surface class, so a
   *  bespoke body (the icon picker) owns 100% of its padding/layout with no `surface` collision. */
  bareSurface?: boolean
  /** Outline the pane in accent @ tint-secondary (the page-location border signal) — opt-in, used by the
   *  block-surface pickers so they read as part of that surface. */
  accentOutline?: boolean
  /** Overrides the surface's content gutter (cx'd after the default) — for a picker that wants its own
   *  inset, e.g. the tight single-field TextPicker. */
  contentClassName?: string
  style?: CSSProperties
}): React.JSX.Element | null {
  const selfManaged = open !== undefined
  const { mounted, closing: exitClosing } = useExitPresence(open ?? true)
  const closing = selfManaged ? exitClosing : closingProp
  const paneRef = useRef<HTMLDivElement>(null)
  const markerRef = useRef<HTMLSpanElement>(null)
  const [pos, setPos] = useState<{
    top?: number
    bottom?: number
    right?: number
    left?: number
    notchInset?: number
    notchInsetBottom?: number
  } | null>(null)
  // The *effective* direction: the requested one, auto-flipped to 'down' when it wouldn't fit the
  // viewport (a sideways pane near the screen edge, an upward pane near the top). Down is the terminal
  // fallback, so flips converge — it never flips away from down.
  const [effDir, setEffDir] = useState<'down' | 'up' | 'left' | 'right'>(direction)

  // The pane hangs off the trigger's right edge and opens down-left (a stable dropdown — the pane
  // doesn't move to center the beak). The beak lands as far right as the corner radius allows
  // (`reserve` = the notch's clamp), so we push the pane's right edge `reserve` past the trigger
  // center — then that clamp-limited beak sits exactly on the trigger. Re-runs on scroll/resize.
  const reserve = radius + notchWidth / 2 + 2
  useLayoutEffect(() => {
    // Freeze the pane's position through the Bloom-out: once closing, a trigger that detached or moved
    // (e.g. a pick re-grouped its row) must not re-measure to zeros and snap the fading pane away.
    if (!selfManaged || !mounted || closing) return
    const trigger = triggerRef?.current ?? markerRef.current?.parentElement
    if (!trigger) return
    const measure = (): void => {
      const t = trigger.getBoundingClientRect()
      const c = t.left + t.width / 2
      // Collision test against the measured pane, then flip so the pane fits: any blocked side → down,
      // and down itself → up only when there's no room below (down is the preferred resting direction).
      const ph = paneRef.current?.offsetHeight ?? 0
      const pw = paneRef.current?.offsetWidth ?? 0
      let eff = direction
      if (direction === 'up' && t.top - GAP - ph < VIEWPORT_MARGIN) eff = 'down'
      else if (direction === 'left' && t.left - GAP - pw < VIEWPORT_MARGIN) eff = 'down'
      else if (direction === 'right' && t.right + GAP + pw > window.innerWidth - VIEWPORT_MARGIN) eff = 'down'
      else if (direction === 'down' && t.bottom + GAP + ph > window.innerHeight - VIEWPORT_MARGIN) eff = 'up'
      setEffDir(eff)
      // Sideways: sit beside the trigger; beak clamped onto its vertical centre (the vertical mirror of
      // the right-anchored dropdown — anchor the far edge, aim the beak `reserve` from it).
      if (eff === 'left' || eff === 'right') {
        const cy = t.top + t.height / 2
        const bottom = Math.max(VIEWPORT_MARGIN, window.innerHeight - cy - reserve)
        if (eff === 'right') setPos({ left: t.right + GAP, bottom, notchInsetBottom: reserve })
        else setPos({ right: window.innerWidth - t.left + GAP, bottom, notchInsetBottom: reserve })
        return
      }
      // Vertical. Centred (icon picker / TextPicker): straddle the trigger, beak centred on it, clamped
      // by the pane half-width so an edge trigger can't push it off-screen. Else the stable right-anchored
      // dropdown, beak clamped onto the trigger centre.
      if (center) {
        const half = pw / 2
        const left = Math.min(Math.max(c, VIEWPORT_MARGIN + half), window.innerWidth - VIEWPORT_MARGIN - half)
        if (eff === 'up') setPos({ bottom: window.innerHeight - t.top + GAP, left })
        else setPos({ top: t.bottom + GAP, left })
        return
      }
      const right = Math.max(VIEWPORT_MARGIN, window.innerWidth - c - reserve)
      if (eff === 'up') setPos({ bottom: window.innerHeight - t.top + GAP, right, notchInset: reserve })
      else setPos({ top: t.bottom + GAP, right, notchInset: reserve })
    }
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(trigger)
    if (paneRef.current) ro.observe(paneRef.current)
    window.addEventListener('scroll', measure, true)
    window.addEventListener('resize', measure)
    return () => {
      ro.disconnect()
      window.removeEventListener('scroll', measure, true)
      window.removeEventListener('resize', measure)
    }
  }, [selfManaged, mounted, reserve, triggerRef, closing, center, direction])

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

  // Render off the EFFECTIVE direction (post-flip), so the beak side + gutter match where the pane sits.
  const up = effDir === 'up'
  const horizontal = effDir === 'left' || effDir === 'right'
  const notchSide = effDir === 'up' ? 'bottom' : effDir === 'left' ? 'right' : effDir === 'right' ? 'left' : 'top'
  const pane = (
    <NotchedPane
      // A bespoke body (bareSurface) or a sideways pane owns its full gutter via contentClassName —
      // the top/bottom `--notch-h` surface gutter is either unwanted or the wrong axis; vertical
      // default panes keep the shared surface gutter.
      className={horizontal || bareSurface ? contentClassName : cx(s.surface, up && s.surfaceUp, contentClassName)}
      animationClass={closing ? dropdownClose : dropdownOpen}
      solid={solid}
      radius={radius}
      notchWidth={notchWidth}
      notchHeight={notchHeight}
      notchCurve={notchCurve}
      notchInsetRight={pos?.notchInset}
      notchInsetBottom={pos?.notchInsetBottom}
      notchSide={notchSide}
      accentOutline={accentOutline}
      style={style}
    >
      {children}
    </NotchedPane>
  )

  // Manual (legacy) — inline, caller-mounted, centered beak.
  if (!selfManaged) {
    return <div className={up ? s.anchorUp : s.anchor}>{pane}</div>
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
          {onDismiss && !closing ? <div className={s.backdrop} data-picker-portal onClick={onDismiss} /> : null}
          <div
            ref={paneRef}
            className={s.layer}
            data-picker-portal
            style={{
              // Vertical panes anchor by `top`; sideways panes by `bottom` (aiming the side beak).
              ...(pos?.top !== undefined ? { top: `${pos.top}px` } : null),
              ...(pos?.bottom !== undefined ? { bottom: `${pos.bottom}px` } : null),
              ...(pos?.left !== undefined
                ? { left: `${pos.left}px`, ...(center ? { transform: 'translateX(-50%)' } : null) }
                : pos?.right !== undefined
                  ? { right: `${pos.right}px` }
                  : null),
              ...(pos ? null : { top: '0' }),
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
