import type { CSSProperties, ReactNode } from 'react'
import { dropdownOpen, dropdownClose } from '../../animations.css'
import { NotchedPane } from '../NotchedPane'
import { cx } from '../../cx'
import * as s from './pickerMenu.css'

// Uses the `dropdown` token (snappier, symmetric Bloom — same keyframes as the menu Bloom, shared with
// AutocompletePanel). The beaked shell is the shared NotchedPane; this stays the picker-flavoured skin.
export function PickerMenu({
  children,
  closing = false,
  solid = false,
  radius = 14,
  notchWidth = 28,
  notchHeight = 8,
  notchCurve = 0.25,
  notchInsetLeft,
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
  /** Beak aim from the pane's left edge (left-anchored hosts); omitted = centered. */
  notchInsetLeft?: number
  style?: CSSProperties
}): React.JSX.Element {
  return (
    <div className={s.anchor}>
      <NotchedPane
        className={s.surface}
        animationClass={closing ? dropdownClose : dropdownOpen}
        solid={solid}
        radius={radius}
        notchWidth={notchWidth}
        notchHeight={notchHeight}
        notchCurve={notchCurve}
        notchInsetLeft={notchInsetLeft}
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
