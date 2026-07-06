import { globalStyle, style } from '@vanilla-extract/css'
import { tintAt, TINT_STEPS } from '../design-system/tokens/tint'

// ── KNOBS — the ViewDropdown button geometry (tune here) ──
const BUTTON = {
  padX: '8px' // horizontal padding around the segment (same both states; the label slot carries the gap)
}

// ── KNOB — the active-view row's highlight ring thickness (px) ──
const HIGHLIGHT_RING = '1px'

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

/** The view button — one padding for both states; the segment's own gap is zeroed so the collapsing
 *  label slot (segmented.css) is the sole icon↔title spacing, and the icon-only state sits flush. */
export const button = style({ paddingInline: BUTTON.padX })
globalStyle(`${button} button`, { gap: 0 })

/** A layout-neutral slot around only the button, so its right-click context menu fires on the button
 *  chrome alone — the open pane is a sibling outside this subtree, so right-clicks there don't reach it. */
export const buttonSlot = style({ display: 'contents' })

/** The active view's row — a tint-primary inset ring (the tile-selection tone) so you can see which
 *  view you're in while the dropdown stays open. Inset, so it rides within the row's radius, no reflow. */
export const activeRow = style({ boxShadow: `inset 0 0 0 ${HIGHLIGHT_RING} ${tintAt('var(--accent)', TINT_STEPS.primary)}` })

/** The ViewPane row's push chevron. It's a <button> in the toolbar's DOM, so `.app-toolbar button`'s
 *  control-tone rule (0,1,1) would paint it bright — the `&&` (0,2,0) pins it to the row's label-secondary
 *  trailing tone, matching the ViewSettings/SettingsPane nav chevrons (bare Icons the rule can't touch). */
export const chevronButton = style({
  border: 'none',
  background: 'none',
  padding: 0,
  cursor: 'default',
  display: 'flex',
  selectors: { '&&': { color: 'var(--label-secondary)' } }
})
