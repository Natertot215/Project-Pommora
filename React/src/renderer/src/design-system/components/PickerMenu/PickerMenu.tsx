import { useRef, type CSSProperties, type ReactNode } from 'react'
import { dropdownOpen, dropdownClose } from '../../animations.css'
import { useExitPresence } from '../../useExitPresence'
import { useDismiss } from '../Popover/Popover'
import { NotchedPane } from '../NotchedPane'
import { cx } from '../../cx'
import * as s from './pickerMenu.css'

const NOOP = (): void => {}

// Uses the `dropdown` token (snappier, symmetric Bloom — same keyframes as the menu Bloom, shared with
// AutocompletePanel). The beaked shell is the shared NotchedPane; this stays the picker-flavoured skin.
//
// Two lifecycle modes:
//  • Self-managed (pass `open` + `onDismiss`): PickerMenu owns mount → Bloom-out → unmount via
//    useExitPresence, and click-away / Escape dismissal via useDismiss. Interaction is frozen during
//    the exit so a mid-close click can't re-fire. The one-liner most pickers want.
//  • Manual (pass `closing`, mount the element yourself): the caller drives the lifecycle — for the
//    few consumers with bespoke close logic (a multi-select picker that stays open on pick).
export function PickerMenu({
  children,
  open,
  onDismiss,
  closing: closingProp = false,
  solid = false,
  radius = 14,
  notchWidth = 28,
  notchHeight = 8,
  notchCurve = 0.25,
  direction = 'down',
  align = 'center',
  style
}: {
  children: ReactNode
  /** Self-managed mode: PickerMenu mounts/exits + wires dismissal off this. Omit for manual mode. */
  open?: boolean
  /** Self-managed dismissal target (outside-click / Escape). */
  onDismiss?: () => void
  /** Manual mode: the caller's exit flag, ridden to the Bloom-out. Ignored when `open` is set. */
  closing?: boolean
  /** The Solid variation: a window-background fill under the frost, reading opaque over any
   *  backdrop (the table's value picker). Default stays pure glass. */
  solid?: boolean
  radius?: number
  notchWidth?: number
  notchHeight?: number
  notchCurve?: number
  /** 'up' hangs the pane ABOVE its trigger with the beak pointing down (bottom-of-pane hosts). */
  direction?: 'down' | 'up'
  /** Horizontal anchor: 'center' over the trigger, or 'end' with the pane's right edge aligned to it
   *  (so a trigger near the container's right edge opens leftward instead of clipping). */
  align?: 'center' | 'end'
  style?: CSSProperties
}): React.JSX.Element | null {
  const selfManaged = open !== undefined
  const { mounted, closing: exitClosing } = useExitPresence(open ?? true)
  const ref = useRef<HTMLDivElement>(null)
  useDismiss(ref, onDismiss ?? NOOP, selfManaged && onDismiss !== undefined && open === true && !exitClosing)
  const closing = selfManaged ? exitClosing : closingProp
  if (selfManaged && !mounted) return null

  const up = direction === 'up'
  const anchorClass = up ? s.anchorUp : align === 'end' ? s.anchorEnd : s.anchor
  return (
    <div ref={ref} className={anchorClass} style={closing ? { pointerEvents: 'none' } : undefined}>
      <NotchedPane
        className={cx(s.surface, up && s.surfaceUp)}
        animationClass={closing ? dropdownClose : dropdownOpen}
        solid={solid}
        radius={radius}
        notchWidth={notchWidth}
        notchHeight={notchHeight}
        notchCurve={notchCurve}
        notchSide={up ? 'bottom' : 'top'}
        style={style}
      >
        {children}
      </NotchedPane>
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
