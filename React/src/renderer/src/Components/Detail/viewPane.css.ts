import { style } from '@vanilla-extract/css'
import { vars as colorVars, inputFieldVar } from '../../design-system/tokens/color.css'
import { text } from '../../design-system/tokens/typography.css'
import { duration, easing } from '../../design-system/tokens/motion'
import { flushAffordance } from '../../design-system/components/menu/menu.css'

const c = colorVars.color

/** Anchored under the toolbar Settings button (the trio cluster is position:relative). Right-aligned,
 *  so the dropdown-menu open animation blooms from the trigger side via --dropdown-origin. */
export const anchor = style({
  position: 'absolute',
  top: 'calc(100% + 6px)',
  right: 0,
  zIndex: 10,
  vars: { '--dropdown-origin': 'top right' }
})

/** The icon + title header row. 2px left inset lands the icon-button's centered dash on the row-icon
 *  column (rows inset their 16px dash by 8px; the 28px button centers its dash at 6px → 2px + 6px = 8px). */
export const header = style({ display: 'flex', alignItems: 'center', gap: '8px', padding: '2px 0 6px 2px' })

/** Square icon button — opens the icon picker. */
export const iconButton = style({
  flex: '0 0 auto',
  width: '28px',
  height: '28px',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  borderRadius: '8px',
  border: 'none',
  background: inputFieldVar,
  cursor: 'default',
  color: c.label.secondary,
  selectors: { '&:hover': { background: c.fill.quaternary } }
})

/** The title interaction-field / input takes the remaining width. */
export const titleField = style({ flex: '1 1 auto', minWidth: 0 })

/** Placeholder dashed-square menu icon (until Nathan specifies the real symbols). */
export const dashIcon = style({
  width: '16px',
  height: '16px',
  borderRadius: '3px',
  border: '1px dashed currentColor',
  opacity: 0.5,
  flex: '0 0 auto'
})

/** Footing actions (New Property, Delete Property) — subline type on the shared gutter-flush affordance
 *  (aligned with the back-row ‹ heading), with a tighter row (min-height + block-padding 4px shorter
 *  than a content row) so the footing reads compact. */
export const footerAction = style([
  text.footnote.emphasized,
  flushAffordance,
  { minHeight: '20px', paddingBlock: '2px' }
])

/** Pins a pane's footer group (divider + action) to the bottom edge; body stays at the top. */
export const footer = style({ marginTop: 'auto' })

/** Destructive row (Delete property) — red label token, overrides the row's primary color. */
export const deleteRow = style({ color: c.solid.red })

/** The pane's header line: the back row takes the width, a trailing icon action rides the right
 *  edge (⊕ create on the list, ⋮ menu on the editor) at the rows' 8px inset. */
export const paneHeader = style({
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between',
  paddingRight: '8px'
})
export const paneHeaderBack = style({ flex: '1 1 auto', minWidth: 0 })

/** Bare 20×20 icon button in the pane header — secondary, lifting to primary on hover. */
export const headerAction = style({
  flex: '0 0 auto',
  width: '20px',
  height: '20px',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  border: 'none',
  background: 'none',
  padding: 0,
  cursor: 'default',
  color: c.label.secondary,
  selectors: { '&:hover': { color: c.label.primary } }
})

/** The "All Properties" disclosure heading — footnote-emphasized, tertiary (A-3). */
export const allHeading = style([text.footnote.emphasized, { color: c.label.tertiary }])

/** The disclosure chevron — the sidebar's twisty, pinned to the pane's beat so the rotate,
 *  the Reveal unfold, and the height-resize land together (E-8). */
export const twisty = style({
  transition: `transform ${duration.base} ${easing.standard}`,
  flex: '0 0 auto'
})
export const twistyOpen = style({ transform: 'rotate(90deg)' })

/** Unassigned registry rows render dimmer than assigned ones (A-3). */
export const allRow = style({ color: c.label.tertiary })

/** The per-row `+` promote affordance (A-5) — bare 16×16, secondary to primary on hover. */
export const rowPlus = style({
  width: '16px',
  height: '16px',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  border: 'none',
  background: 'none',
  padding: 0,
  cursor: 'default',
  color: c.label.secondary,
  selectors: { '&:hover': { color: c.label.primary } }
})
