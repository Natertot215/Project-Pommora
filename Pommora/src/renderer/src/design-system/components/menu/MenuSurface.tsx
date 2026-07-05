import type { ReactNode } from 'react'
import { cx } from '../../cx'
import { dropdownMenu, dropdownMenuClosing } from '../../animations.css'
import { NotchedPane } from '../NotchedPane'
import * as s from './menuSurface.css'

/**
 * The shared "large dropdown" container — the beaked glass shell (NotchedPane) with rounded
 * corners and the standard inside gutter (MENU_GUTTER, matching the sidebar's edge padding) so its
 * menu items and dividers align into one empty gutter, carrying the dropdown-menu open animation.
 * Every large dropdown (ViewPane, future pickers) consumes this, keeping the dropdown chrome DRY.
 * `notchInsetRight` aims the beak at the trigger (from the pane's right edge); omitted = centered.
 */
export function MenuSurface({
  children,
  className,
  closing = false,
  notchInsetRight
}: {
  children: ReactNode
  className?: string
  /** Play the retract (close) animation instead of the open — the parent keeps it mounted until it ends. */
  closing?: boolean
  notchInsetRight?: number
}): React.JSX.Element {
  return (
    <NotchedPane
      className={cx(s.surface, className)}
      animationClass={closing ? dropdownMenuClosing : dropdownMenu}
      radius={12}
      notchInsetRight={notchInsetRight}
    >
      {children}
    </NotchedPane>
  )
}
