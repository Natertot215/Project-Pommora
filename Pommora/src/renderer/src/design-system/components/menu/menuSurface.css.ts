import { globalStyle, style } from '@vanilla-extract/css'
import { vars as colorVars } from '../../tokens/color.css'
import { titleText } from './menu.css'

const c = colorVars.color

/**
 * The inside horizontal gutter shared by every large dropdown. Matches the sidebar's edge padding
 * (Sidebar.css) so menu items and dividers align into the same empty gutter. Single source — all
 * dropdown surfaces route here, so the gutter never drifts between them.
 */
export const MENU_GUTTER = '10px'

/** The large-dropdown shell: glass (from NotchedPane) + rounded corners + the shared gutter, floored
 *  at a minimum width so a sparse pane never shrink-wraps narrow. The top gutter clears the beak
 *  band via the shell's published --notch-h. */
export const surface = style({
  borderRadius: '12px',
  padding: `6px ${MENU_GUTTER}`,
  paddingTop: 'calc(var(--notch-h, 0px) + 6px)',
  overflow: 'hidden',
  minWidth: '225px',
})

// Dropdown row titles read at label-control — one source for every dropdown surface (the `item`
// primitive is shared with the sidebar, which keeps its own label-primary title outside a surface).
// The picker-menu option is set to control to match this.
globalStyle(`${surface} .${titleText}`, { color: c.label.control })
