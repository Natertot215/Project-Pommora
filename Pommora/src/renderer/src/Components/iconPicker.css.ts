import { style } from '@vanilla-extract/css'
import { vars } from '@renderer/design-system/tokens'
import { tintAt, TINT_STEPS } from '@renderer/design-system/tokens'

const CELL = 34

/** The pane's SOLE surface class (PickerMenu `bareSurface`) — owns 100% of the gutter. Padding equals
 *  the inter-row gap, so the search sits with the same space above it as below it to the divider; the
 *  uniform inset also clears the beak (≥ its depth) on whichever of the four edges it rides. */
export const content = style({
  display: 'flex',
  flexDirection: 'column',
  alignItems: 'stretch',
  gap: 8,
  padding: 8,
  width: 'var(--icon-picker-w, 224px)',
  boxSizing: 'border-box'
})

// The beak eats into the gutter on the edge it rides, so add its depth (`--notch-h`) back to that
// side — the search/content then sits a full, uniform gap in from the visible pane body on every edge.
// Keyed to the requested direction (the near-edge auto-flip case is a minor cosmetic exception).
export const beakDown = style({ paddingTop: 'calc(8px + var(--notch-h, 0px))' })
export const beakUp = style({ paddingBottom: 'calc(8px + var(--notch-h, 0px))' })
export const beakLeft = style({ paddingLeft: 'calc(8px + var(--notch-h, 0px))' })
export const beakRight = style({ paddingRight: 'calc(8px + var(--notch-h, 0px))' })

export const search = style({
  width: '100%',
  padding: '6px 8px',
  boxSizing: 'border-box',
  textAlign: 'left',
  // The body portal escapes the app's type context, so pin font + line-height (else the caret inherits
  // an oversized line box and sits misaligned).
  fontFamily: 'inherit',
  fontSize: 13,
  lineHeight: 1.2,
  color: vars.color.label.primary,
  background: vars.color.fill.secondary,
  border: '1px solid transparent',
  borderRadius: 8,
  outline: 'none',
  selectors: {
    '&::placeholder': { color: vars.color.label.tertiary },
    // Tint-secondary outline highlight only while the caret is in the field.
    '&:focus': { borderColor: tintAt('var(--accent)', TINT_STEPS.secondary) }
  }
})

export const separator = style({
  width: '100%',
  height: 1,
  flex: '0 0 auto',
  background: vars.color.separator.border
})

/** Favorites: a rounded, outlined box — a second input field holding the favorite icons. Its
 *  divider-color outline replaces the flanking dividers; `overflow: hidden` clips the inner scroll to
 *  the corners so the border stays crisp under the eclipse mask. Tight vertical padding. */
export const favorites = style({
  width: '100%',
  flex: '0 0 auto',
  boxSizing: 'border-box',
  padding: '2px 4px',
  border: `1.5px solid ${vars.color.separator.border}`,
  borderRadius: 8,
  overflow: 'hidden'
})

/** The inner horizontal, drag-reorderable strip — scrolls with the bare `overflow-eclipse` fade (not
 *  the OverflowScroll wrapper, so it never snaps back on hover-off). */
export const favScroll = style({
  display: 'flex',
  gap: 2,
  overflowX: 'auto',
  overflowY: 'hidden',
  scrollbarWidth: 'none',
  vars: { '--eclipse-fade': '16px' },
  selectors: { '&::-webkit-scrollbar': { display: 'none' } }
})

/** The vertical scroll region — holds the favorites strip AND the full-set grid, so favorites scroll
 *  together with the icons under one eclipse fade. Fixed height reserves the ~6-row viewport; explicit
 *  width so `cols` measures a real box (a bare flex item collapses to its absolute rows' zero width). */
export const grid = style({
  position: 'relative',
  display: 'flex',
  flexDirection: 'column',
  gap: 8,
  width: '100%',
  height: 'var(--icon-picker-h, 204px)',
  overflowY: 'auto',
  overflowX: 'hidden',
  scrollbarWidth: 'none',
  vars: { '--eclipse-fade': '20px' },
  selectors: { '&::-webkit-scrollbar': { display: 'none' } }
})

/** The virtualized icon list inside the scroll region — its height is the full virtual extent; rows are
 *  absolutely positioned within it (offset by the virtualizer's scrollMargin past the favorites strip). */
export const list = style({ position: 'relative', width: '100%', flex: '0 0 auto' })

export const row = style({ position: 'absolute', top: 0, left: 0, display: 'flex' })

export const cell = style({
  width: CELL,
  height: CELL,
  flex: '0 0 auto',
  display: 'grid',
  placeItems: 'center',
  border: 'none',
  background: 'transparent',
  borderRadius: 8,
  color: vars.color.label.control,
  cursor: 'pointer',
  selectors: {
    '&:hover': { background: vars.color.fill.secondary }
  }
})

export const cellSelected = style({
  color: 'var(--accent)',
  background: tintAt('var(--accent)', TINT_STEPS.quaternary)
})
