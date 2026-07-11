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

/** The dropdown pane CONTEXT — the shared gutter + row-title tone every dropdown pane
 *  reads. Split from the shell so anchored pickers (PickerMenu hosts) compose the SAME
 *  context as MenuSurface without inheriting the shell's minimum width; the && lets it
 *  outrank a host shell's own gutter. */
export const paneContext = style({
  selectors: {
    '&&': { paddingLeft: MENU_GUTTER, paddingRight: MENU_GUTTER }
  }
})

// Dropdown row titles read at label-control — one source for every dropdown surface (the `item`
// primitive is shared with the sidebar, which keeps its own label-primary title outside a surface).
globalStyle(`${paneContext} .${titleText}`, { color: c.label.primary })

/** The large-dropdown shell: glass (from NotchedPane) + rounded corners + the shared pane
 *  context, floored at a minimum width so a sparse pane never shrink-wraps narrow. The top
 *  gutter clears the beak band via the shell's published --notch-h. */
export const surface = style([
  paneContext,
  {
    borderRadius: '12px',
    paddingTop: 'calc(var(--notch-h, 0px) + 6px)',
    paddingBottom: '6px',
    overflow: 'hidden',
    minWidth: '225px'
  }
])

