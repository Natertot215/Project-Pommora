import { globalStyle, style } from '@vanilla-extract/css'
import { vars as colorVars } from '../design-system/tokens/color.css'

const c = colorVars.color

// ── KNOBS — the ViewDropdown button geometry (tune here) ──
const BUTTON = {
  iconPadX: '8px', // icon-only variant: horizontal padding around the glyph
  labeledPadX: '8px', // labeled variant: horizontal padding
  labeledWidth: '128px' // labeled variant: one fixed width; the name overflow-scrolls inside
}

/** The button + its anchored dropdown share this relative box, so the pane hangs off the button
 *  (not the trio cluster). Sits left of the trio via the toolbar's inter-cluster gap. */
export const wrapper = style({
  position: 'relative',
  display: 'flex',
  alignItems: 'center',
  pointerEvents: 'auto',
  WebkitAppRegion: 'no-drag'
} as Parameters<typeof style>[0])

/** The dropdown anchor — hangs straight down, centred on the button (the beak points up at its
 *  centre via the surface's default centred notch), blooming from the top-centre. */
export const anchor = style({
  position: 'absolute',
  top: 'calc(100% + 6px)',
  left: '50%',
  transform: 'translateX(-50%)',
  zIndex: 10,
  vars: { '--dropdown-origin': 'top center' }
})

/** The view-list menu — drops the base menu's bottom padding so the +/… footer sits close to the
 *  pane's bottom edge (the surface keeps its own small gutter). */
export const paneMenu = style({ paddingBottom: 0 })

/** Icon-only button padding. */
export const iconPad = style({ paddingInline: BUTTON.iconPadX })

/** Labeled button (Show Title) — emphasized name at a 6px icon↔text gap (2px over the segment base). */
export const labeled = style({ paddingInline: BUTTON.labeledPadX })
globalStyle(`${labeled} button`, { gap: '6px' })
globalStyle(`${labeled} button span`, { fontWeight: 500 })

/** The ViewPane row's push chevron — a bare button in the row's secondary tone. */
export const chevronButton = style({
  border: 'none',
  background: 'none',
  padding: 0,
  cursor: 'default',
  display: 'flex',
  color: 'var(--label-secondary)'
})
