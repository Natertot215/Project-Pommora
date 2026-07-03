import { style } from '@vanilla-extract/css'
import { vars as colorVars, inputFieldVar } from '../../design-system/tokens/color.css'
import { text } from '../../design-system/tokens/typography.css'
import { duration, easing } from '../../design-system/tokens/motion'
import { flushAffordance } from '../../design-system/components/menu/menu.css'

const c = colorVars.color

// ═══════════════════════════════════════════════════════════════════════════
// KNOBS — every ViewPane tunable, grouped by what it controls. Tune here;
// the styles below (ordered top-to-bottom as the pane renders) only consume.
// ═══════════════════════════════════════════════════════════════════════════

/** — COLOR — */
const COLOR = {
  headerAction: c.label.tertiary, // ⊕ / ⋮ at rest
  headerActionHover: c.label.control, // ⊕ / ⋮ hovered
  allHeading: c.label.tertiary, // "All Properties" heading (text + its chevron)
  allRow: c.label.tertiary, // unassigned registry rows
  rowPlus: c.label.tertiary, // a registry row's + at rest
  rowPlusHover: c.label.primary, // …hovered
  dragHighlight: c.state.hover, // the unassign area tint while dragging out
  eye: c.label.secondary, // the Visibility eye toggle (shown rows): secondary + ghost at rest,
  // un-ghosts on hover (no color shift); the glyph swaps open ↔ off
  eyeHidden: c.label.tertiary // a hidden row's eye: tertiary, riding the row's ghost (single dim)
}

/** — SIZING — (px boxes; the glyphs inside are ICON's) */
const SIZE = {
  headerActionWidth: 20, // ⊕ / ⋮ horizontal hit target (height hugs the glyph)
  rowPlusBox: 16, // the registry row's + hit target
  eyeBox: 16, // the Visibility pane's eye hit target
  iconPickerButton: 28, // the title header's square icon button
  dashIcon: 16, // the placeholder dashed square
  dragHighlightRadius: 6 // the unassign tint's corner radius
}

/** — PADDING — (px) */
const PAD = {
  backRowBlock: 4 // back-row vertical padding — THE pane-header height knob (no min-height floor)
}

/** — ICONS — glyph sizes, consumed by PropertiesPane/ViewPane TSX. The back-row's own
 *  ‹ chevron is the shared MenuBackRow's (12, in Menu.tsx) — not a pane-local knob. */
export const ICON = {
  add: 12, // the header ⊕ (square-plus)
  editorMenu: 16, // the editor header's ⋮
  doc: 12, // the property-type icon on every row (assigned · registry · type picker)
  rowChevron: 16, // the trailing › on navigable rows (root entries + assigned rows)
  rootEntry: 16, // the root menu's leading icons (Properties · Visibility · …)
  twisty: 12, // the All Properties disclosure chevron
  rowPlus: 12, // the registry row's + glyph
  eye: 14 // the Visibility pane's eye / eye-off glyph
}

// ═══════════════════════════════════════════════════════════════════════════
// § SHELL — the dropdown anchor under the toolbar Settings button
// ═══════════════════════════════════════════════════════════════════════════

/** Anchored under the toolbar Settings button (the trio cluster is position:relative). Right-aligned,
 *  so the dropdown-menu open animation blooms from the trigger side via --dropdown-origin. */
export const anchor = style({
  position: 'absolute',
  top: 'calc(100% + 6px)',
  right: 0,
  zIndex: 10,
  vars: { '--dropdown-origin': 'top right' }
})

// ═══════════════════════════════════════════════════════════════════════════
// § TITLE HEADER — the root menu's icon + inline-rename title row
// ═══════════════════════════════════════════════════════════════════════════

/** The icon + title header row. 2px left inset lands the icon-button's centered dash on the row-icon
 *  column (rows inset their 16px dash by 8px; the 28px button centers its dash at 6px → 2px + 6px = 8px). */
export const header = style({ display: 'flex', alignItems: 'center', gap: '8px', padding: '2px 0 6px 2px' })

/** Square icon button — opens the icon picker. */
export const iconButton = style({
  flex: '0 0 auto',
  width: `${SIZE.iconPickerButton}px`,
  height: `${SIZE.iconPickerButton}px`,
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
  width: `${SIZE.dashIcon}px`,
  height: `${SIZE.dashIcon}px`,
  borderRadius: '3px',
  border: '1px dashed currentColor',
  opacity: 0.5,
  flex: '0 0 auto'
})

// ═══════════════════════════════════════════════════════════════════════════
// § PANE HEADER — the ‹ back row + the trailing ⊕ / ⋮ action
// ═══════════════════════════════════════════════════════════════════════════

/** The pane's header line: the back row takes the width, a trailing icon action rides the right
 *  edge (⊕ create on the list, ⋮ menu on the editor), its right edge flush with the divider's
 *  end — no row padding (Nathan's call). */
export const paneHeader = style({
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between'
})
export const paneHeaderBack = style({ flex: '1 1 auto', minWidth: 0 })

/** THE ViewPane back-row vertical-geometry knob — this pane only. Drops the base row's 24px
 *  min-height floor, so row height = the caption line + 2 × PAD.backRowBlock. */
export const backRowPad = style({ paddingBlock: `${PAD.backRowBlock}px`, minHeight: 0 })

/** Bare header icon button (⊕ create, ⋮ menu) — no vertical box beyond the glyph (a fixed
 *  height held the header taller than the back row); width keeps the horizontal hit target. */
export const headerAction = style({
  flex: '0 0 auto',
  width: `${SIZE.headerActionWidth}px`,
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  border: 'none',
  background: 'none',
  padding: 0,
  cursor: 'default',
  color: COLOR.headerAction,
  transition: `color ${duration.fast} ${easing.standard}`,
  selectors: { '&:hover': { color: COLOR.headerActionHover } }
})

// ═══════════════════════════════════════════════════════════════════════════
// § ALL PROPERTIES — the bottom-pinned disclosure block + its registry rows
// (assigned rows carry no pane-local style — they're menu.css items + flushTrailing)
// ═══════════════════════════════════════════════════════════════════════════

/** The elastic gap above the All Properties block: closed it absorbs the pane floor's slack
 *  (the block reads bottom-pinned); open it collapses on the pane's beat, so the heading RISES
 *  to meet the assigned rows while its list unfolds beneath. */
export const allSpacer = style({
  flex: '1 1 0px',
  transition: `flex-grow ${duration.base} ${easing.standard}`
})
export const allSpacerCollapsed = style({ flexGrow: 0 })

/** The "All Properties" disclosure heading — footnote-emphasized (A-3), its chevron flush at
 *  the gutter edge like the back-row's ‹ (the shared flush affordance). */
export const allHeading = style([text.footnote.emphasized, flushAffordance, { color: COLOR.allHeading }])

/** The disclosure chevron — the sidebar's twisty, pinned to the pane's beat so the rotate,
 *  the Reveal unfold, and the height-resize land together (E-8). */
export const twisty = style({
  transition: `transform ${duration.base} ${easing.standard}`,
  flex: '0 0 auto'
})
export const twistyOpen = style({ transform: 'rotate(90deg)' })

/** Unassigned registry rows render dimmer than assigned ones (A-3). */
export const allRow = style({ color: COLOR.allRow })

/** The per-row `+` promote affordance (A-5). */
export const rowPlus = style({
  width: `${SIZE.rowPlusBox}px`,
  height: `${SIZE.rowPlusBox}px`,
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  border: 'none',
  background: 'none',
  padding: 0,
  cursor: 'default',
  color: COLOR.rowPlus,
  selectors: { '&:hover': { color: COLOR.rowPlusHover } }
})

// ═══════════════════════════════════════════════════════════════════════════
// § VISIBILITY (HiddenPane) — the ghosted hidden zone + per-row eye toggle
// ═══════════════════════════════════════════════════════════════════════════

/** The picked-up row fades to the ghost opacity — muted in place, never displaced. Shared by both
 *  panes' RowShell; declared here so the hidden-row ghost below can reference it (source order). */
export const rowDragging = style({ opacity: 'var(--state-ghost)' })

/** Hidden rows read de-emphasized via the shared ghost opacity (the drag-dim token — Nathan's
 *  call: `--state-ghost`, not the muted veil). The ghost IS the shown/hidden boundary — no
 *  heading (Nathan's call). Reset to full opacity while this row is the drag subject: `rowDragging`
 *  already dims the wrapper to the ghost, and two stacked 60% layers composite to 36% (breaker
 *  L-3) — the inner row rides full so the net dim is the single intended ghost. */
export const hiddenRow = style({
  opacity: 'var(--state-ghost)',
  selectors: { [`${rowDragging} &`]: { opacity: 1 } }
})

/** The hidden zone sits directly below the shown rows and grows into the pane's slack (rows
 *  top-aligned — Nathan's call: placed below, NOT bottom-pinned), so the drag-to-hide area
 *  highlight covers the empty space beneath them even while nothing's hidden yet. */
export const hiddenZone = style({ flex: '1 1 auto' })

/** The eye toggle — secondary + ghost at rest, un-ghosting on hover (no color shift); the glyph
 *  swaps open ↔ off (the pair passes reversed in JSX on a hidden row). On a hidden row the eye is
 *  tertiary and its own opacity resets to 1 so it rides ONLY the row's ghost (never double-dims). */
export const eyeButton = style({
  width: `${SIZE.eyeBox}px`,
  height: `${SIZE.eyeBox}px`,
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  border: 'none',
  background: 'none',
  padding: 0,
  cursor: 'default',
  color: COLOR.eye,
  opacity: 'var(--state-ghost)',
  transition: `opacity ${duration.fast} ${easing.standard}`,
  selectors: {
    '&:hover': { opacity: 1 },
    [`${hiddenRow} &`]: { color: COLOR.eyeHidden, opacity: 1 }
  }
})
export const eyeRestGlyph = style({
  display: 'flex',
  selectors: { [`${eyeButton}:hover &`]: { display: 'none' } }
})
export const eyeHoverGlyph = style({
  display: 'none',
  selectors: { [`${eyeButton}:hover &`]: { display: 'flex' } }
})

// ═══════════════════════════════════════════════════════════════════════════
// § DRAG CHROME — the two-region drag's box, highlight, and source dim
// ═══════════════════════════════════════════════════════════════════════════

/** The pane drag's positioning context (drop line) — fills the slot so the elastic spacer
 *  has the floor's slack to absorb. */
export const paneDnd = style({
  position: 'relative',
  display: 'flex',
  flexDirection: 'column',
  flex: '1 1 auto'
})

/** The unassign target's area highlight (C-4) — the whole all-group tints, no insertion line. */
export const allHighlight = style({
  background: COLOR.dragHighlight,
  borderRadius: `${SIZE.dragHighlightRadius}px`
})
