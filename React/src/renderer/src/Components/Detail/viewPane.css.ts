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

/** The pane's header line: the back row takes the width, a trailing icon action rides the right
 *  edge (⊕ create on the list, ⋮ menu on the editor) at the rows' 8px inset. */
export const paneHeader = style({
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between',
  paddingRight: '8px'
})
export const paneHeaderBack = style({ flex: '1 1 auto', minWidth: 0 })

/** Bare 20×20 icon button in the pane header — secondary lifting to primary on hover, on the
 *  Add-Banner button's color beat. */
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
  transition: `color ${duration.fast} ${easing.standard}`,
  selectors: { '&:hover': { color: c.label.primary } }
})

/** The "All Properties" disclosure heading — footnote-emphasized, tertiary (A-3), its chevron
 *  flush at the gutter edge like the back-row's ‹ (the shared flush affordance). */
export const allHeading = style([text.footnote.emphasized, flushAffordance, { color: c.label.tertiary }])

/** The disclosure chevron — the sidebar's twisty, pinned to the pane's beat so the rotate,
 *  the Reveal unfold, and the height-resize land together (E-8). */
export const twisty = style({
  transition: `transform ${duration.base} ${easing.standard}`,
  flex: '0 0 auto'
})
export const twistyOpen = style({ transform: 'rotate(90deg)' })

/** Unassigned registry rows render dimmer than assigned ones (A-3). */
export const allRow = style({ color: c.label.tertiary })

/** The elastic gap above the All Properties block: closed it absorbs the pane floor's slack
 *  (the block reads bottom-pinned); open it collapses on the pane's beat, so the heading RISES
 *  to meet the assigned rows while its list unfolds beneath. */
export const allSpacer = style({
  flex: '1 1 0px',
  transition: `flex-grow ${duration.base} ${easing.standard}`
})
export const allSpacerCollapsed = style({ flexGrow: 0 })

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

/** The pane drag's positioning context (drop line) — fills the slot so the elastic spacer
 *  has the floor's slack to absorb. */
export const paneDnd = style({
  position: 'relative',
  display: 'flex',
  flexDirection: 'column',
  flex: '1 1 auto'
})

/** The unassign target's area highlight (C-4) — the whole all-group tints, no insertion line. */
export const allHighlight = style({ background: c.state.hover, borderRadius: '6px' })

/** The picked-up row fades to the ghost opacity — muted in place, never displaced. */
export const rowDragging = style({ opacity: 'var(--state-ghost)' })
