import type { ReactNode } from 'react'
import { cx } from '../../cx'
import { dropdownMenu, dropdownMenuClosing } from '../../animations.css'
import { GlassPane } from '../../materials/glass-pane'
import * as s from './menuSurface.css'

/**
 * The shared "large dropdown" container — a frosted glass panel with rounded corners and the
 * standard inside gutter (MENU_GUTTER, matching the sidebar's edge padding) so its menu items and
 * dividers align into one empty gutter, carrying the dropdown-menu open animation. Every large
 * dropdown (ViewPane, future pickers) consumes this, keeping the dropdown chrome DRY.
 */
export function MenuSurface({
  children,
  className,
  closing = false
}: {
  children: ReactNode
  className?: string
  /** Play the retract (close) animation instead of the open — the parent keeps it mounted until it ends. */
  closing?: boolean
}): React.JSX.Element {
  return (
    <GlassPane className={cx(s.surface, closing ? dropdownMenuClosing : dropdownMenu, className)}>{children}</GlassPane>
  )
}
