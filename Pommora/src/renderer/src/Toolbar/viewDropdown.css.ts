import { globalStyle, style } from '@vanilla-extract/css'
import { vars as colorVars } from '../design-system/tokens/color.css'

const c = colorVars.color

// ── KNOBS — the ViewDropdown button geometry (tune here) ──
const BUTTON = {
  padX: '8px' // horizontal padding around the segment (same both states; the label slot carries the gap)
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

/** The view-list menu — fills the pane's reserved square (so the footer can pin to the bottom) and drops
 *  the base menu's bottom padding so the +/… footer sits close to the pane's bottom edge. */
export const paneMenu = style({ flex: 1, paddingBottom: 0 })

/** The view rows — grow to eat the reserved square (footer pinned below), but never shrink past their
 *  own height, so a list longer than the square pushes the pane taller (then the slot scrolls). */
export const rowsFill = style({ flex: '1 0 auto', display: 'flex', flexDirection: 'column' })

/** The view button — one padding for both states; the segment's own gap is zeroed so the collapsing
 *  label slot (segmented.css) is the sole icon↔title spacing, and the icon-only state sits flush. */
export const button = style({ paddingInline: BUTTON.padX })
globalStyle(`${button} button`, { gap: 0 })

/** A layout-neutral slot around only the button, so its right-click context menu fires on the button
 *  chrome alone — the open pane is a sibling outside this subtree, so right-clicks there don't reach it. */
export const buttonSlot = style({ display: 'contents' })

/** The ViewPane row's push chevron — a bare button that inherits the row's trailing-cluster tone (the
 *  `side` span's label-secondary), the same source the ViewSettings nav chevron reads. No own color. */
export const chevronButton = style({
  border: 'none',
  background: 'none',
  padding: 0,
  cursor: 'default',
  display: 'flex'
})
