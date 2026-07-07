import { globalStyle, style } from '@vanilla-extract/css'
import { vars as colorVars, inputFieldVar } from '../../design-system/tokens/color.css'
import { text } from '../../design-system/tokens/typography.css'
import { duration, easing } from '../../design-system/tokens/motion'
import { flushAffordance, accessoryButton, accessoryGhostRest, titleText } from '../../design-system/components/menu/menu.css'
import { surface } from '../../design-system/components/menu/menuSurface.css'

const c = colorVars.color

// ═══════════════════════════════════════════════════════════════════════════
// KNOBS — every ViewPane tunable, grouped by what it controls. Tune here;
// the styles below (ordered top-to-bottom as the pane renders) only consume.
// ═══════════════════════════════════════════════════════════════════════════

/** — COLOR — */
const COLOR = {
  headingLabel: c.label.tertiary, // section-heading TEXT — "Options", "Format", "All Properties" (the dimmest tier)
  actionLabel: c.label.tertiary, // interactive SYMBOLS — icon-picker · eye toggle · recolor palette · Options + · header ⊕/⋮ · promote + (eye/palette add their own ghost-opacity rest; the glyph swaps open ↔ off)
  allRow: c.label.secondary, // unassigned registry rows — dimmer than assigned (primary), brighter than the heading (tertiary)
  iconHover: c.state.hover, // the shared fill behind any pane icon-button on hover (not a glyph shift)
  dragHighlight: c.state.hover, // the unassign area tint while dragging out
  eyeHidden: c.label.tertiary // a hidden row's eye: tertiary, riding the row's ghost (single dim)
}

/** — SIZING — (px boxes; the glyphs inside are ICON's) */
const SIZE = {
  topRowActionWidth: 20, // TopRow ⊕ / ⋮ horizontal hit target (height hugs the glyph)
  iconPickerButton: 28, // the title header's square icon button
  dashIcon: 16, // the placeholder dashed square
  dragHighlightRadius: 6 // the unassign tint's corner radius
}

/** — OPTION EDITOR — (Select/Multi option list; px) */
const OPTION = {
  gapAroundLabel: 6, // "Options" → first chip (the gap ABOVE "Options" is the header's own bottom pad)
  gapBetweenChips: 6, // chip → chip
  chipPadX: 6, // option chip horizontal padding — retunes the shared chip-label default, this pane only
  addBox: 20, // the "Options" + hit target (its glyph is ICON.optionsAdd)
  groupGap: 12 // status only: gap between one group's block (heading + chips) and the next
}

/** — ICONS — glyph sizes, consumed by PropertiesPane/ViewPane TSX. The TopRow's own
 *  ‹ chevron is the shared MenuTopRow's (12, in Menu.tsx) — not a pane-local knob. */
export const ICON = {
  add: 14, // the header ⊕ (square-plus) — sized to the back-row heading (13px), per Nathan
  editorMenu: 14, // the editor header's ⋮ — sized to the back-row heading (13px), per Nathan
  doc: 12, // the property-type icon on every row (assigned · registry · type picker)
  rowChevron: 16, // the trailing › on navigable rows (root entries + assigned rows)
  rootEntry: 16, // the root menu's leading icons (Properties · Visibility · …)
  twisty: 12, // the All Properties disclosure chevron
  rowPlus: 12, // the registry row's + glyph
  eye: 14, // the Visibility pane's eye / eye-off glyph
  optionsAdd: 12, // the option editor's "Options" + glyph
  palette: 14 // the option row's hover recolor glyph
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
  color: COLOR.actionLabel,
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
// § TOPROW — the ‹ back row + its trailing ⊕ / ⋮ action
// ═══════════════════════════════════════════════════════════════════════════

/** The TopRow's trailing action (⊕ create / ⋮ menu) — the shared accessory recipe, retuned for the
 *  TopRow: width-only (height hugs the glyph), right-aligned to the gutter edge, secondary tone as a
 *  member of the back-row heading. The `&&` clears the `.app-toolbar button` control-tone default. */
export const topRowAction = style([
  accessoryButton,
  {
    flex: '0 0 auto',
    width: `${SIZE.topRowActionWidth}px`,
    height: 'auto',
    justifyContent: 'flex-end',
    selectors: { '&&': { color: c.label.secondary } }
  }
])

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

/** The "All Properties" disclosure row — a bare clickable line whose LABEL rides `optionsLabel` (DRY
 *  with the "Options"/"Format" section headings), its chevron flush at the gutter edge. It's not a
 *  MenuItem, so its text escapes the surface's primary titleText tone and reads at the heading tier. */
export const allHeadingRow = style({
  display: 'flex',
  alignItems: 'center',
  gap: '4px',
  width: '100%',
  minHeight: '24px',
  padding: '6px 6px',
  paddingLeft: 0,
  border: 'none',
  background: 'none',
  cursor: 'default'
})

/** The disclosure chevron — the sidebar's twisty, pinned to the pane's beat so the rotate,
 *  the Reveal unfold, and the height-resize land together (E-8). */
export const twisty = style({
  transition: `transform ${duration.base} ${easing.standard}`,
  flex: '0 0 auto'
})
export const twistyOpen = style({ transform: 'rotate(90deg)' })

/** Unassigned registry rows render dimmer than assigned ones (A-3). */
export const allRow = style({ color: COLOR.allRow })

// The row's LABEL rides the surface's primary titleText global (`.surface .titleText`, 0-2-0); beat it
// with a 0-3-0 scope so an unassigned row's title settles one tier down at secondary, matching its icon.
globalStyle(`.${surface} .${allRow} .${titleText}`, { color: c.label.secondary })

/** The per-row `+` promote affordance (A-5) — the shared accessory recipe at the 16px box. */
export const rowPlus = accessoryButton

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

/** The eye toggle — the action-symbol color + ghost at rest, un-ghosting on hover (no color shift);
 *  the glyph swaps open ↔ off (the pair passes reversed in JSX on a hidden row). On a hidden row it
 *  rides eyeHidden + resets its own opacity to 1, so it dims by ONLY the row's ghost (never double-dims). */
export const eyeButton = style([
  accessoryButton,
  accessoryGhostRest,
  { selectors: { [`${hiddenRow} &`]: { color: COLOR.eyeHidden, opacity: 1 } } }
])
export const eyeRestGlyph = style({
  display: 'flex',
  selectors: { [`${eyeButton}:hover &`]: { display: 'none' } }
})
export const eyeHoverGlyph = style({
  display: 'none',
  selectors: { [`${eyeButton}:hover &`]: { display: 'flex' } }
})

/** Title's inert eye — the same glyph + box for visual parity with the other rows, but it never
 *  hides: no hover-preview swap, no hover fill, no pointer (clicking does nothing). Sits at the rest
 *  ghost opacity so it reads like every other row's resting eye. */
export const eyeInert = style([
  accessoryButton,
  {
    cursor: 'default',
    opacity: 'var(--state-ghost)',
    selectors: { '&:hover': { background: 'transparent', opacity: 'var(--state-ghost)' } }
  }
])

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

// ═══════════════════════════════════════════════════════════════════════════
// § OPTION EDITOR — the Select / Multi-Select option list in a property's editor
// ═══════════════════════════════════════════════════════════════════════════

/** The option list container, below the InlineEditHeader (whose bottom pad sets the gap above). */
export const optionEditor = style({ display: 'flex', flexDirection: 'column' })

/** Status only — the grouped variant: one block per group (heading + its chips), stacked with a gap.
 *  Each block reuses `optionsRow` / `optionsLabel` / `optionList` / `optionRow` from the flat editor. */
export const statusGroups = style({ display: 'flex', flexDirection: 'column', gap: `${OPTION.groupGap}px` })
export const statusGroup = style({ display: 'flex', flexDirection: 'column' })

/** The "Options" row — label left, the always-shown + right. */
export const optionsRow = style({ display: 'flex', alignItems: 'center', justifyContent: 'space-between' })

/** The "Options" heading + the Status group labels — footnote-semibold (Nathan's call: a step heavier
 *  than the All Properties / back-row headings), the shared heading-label color. */
export const optionsLabel = style([text.footnote.semibold, { color: COLOR.headingLabel }])

/** The always-shown + that appends an option — the shared action-symbol color, brightening on hover. */
export const optionsAdd = style([accessoryButton, { width: `${OPTION.addBox}px`, height: `${OPTION.addBox}px` }])

/** Status only — the per-group + . Reuses the "Options" + button, hidden until you hover the group
 *  (its heading or its chips), per Nathan's reveal. Tertiary at rest, brightening on direct hover; the
 *  `&&` clears `.app-toolbar button`'s control-tone default (0,1,1) so rest reads genuinely tertiary. */
export const groupAdd = style([
  optionsAdd,
  {
    opacity: 0,
    transition: `opacity ${duration.fast} ${easing.standard}, background ${duration.fast} ${easing.standard}, color ${duration.fast} ${easing.standard}`,
    selectors: {
      [`${statusGroup}:hover &`]: { opacity: 1 },
      '&&': { color: c.label.tertiary },
      '&:hover': { color: c.label.secondary }
    }
  }
])

/** The chip list — full-width rows (chip left, hover recolor icon at the right edge), the inter-chip
 *  gap between them, the "Options"→chips gap on top. */
export const optionList = style({
  display: 'flex',
  flexDirection: 'column',
  position: 'relative', // the drag drop-line positions against this
  gap: `${OPTION.gapBetweenChips}px`,
  paddingTop: `${OPTION.gapAroundLabel}px`,
  vars: { '--chip-pad-x': `${OPTION.chipPadX}px` }
})

/** One option's row — chip left, the hover palette icon pushed to the right edge. */
export const optionRow = style({ display: 'flex', alignItems: 'center', justifyContent: 'space-between' })

/** The inline add/rename caret — bare input inside the chip, which owns the font, padding, and fill. */
export const optionInput = style({
  background: 'transparent',
  border: 'none',
  outline: 'none',
  padding: 0,
  margin: 0,
  color: 'inherit',
  font: 'inherit'
})

/** The recolor icon's positioning context — the ColorPicker anchors (centered, below) to this. */
export const paletteAnchor = style({ position: 'relative', display: 'flex', alignItems: 'center' })

/** The per-row recolor icon — mirrors the Visibility eye: the action-symbol color, hidden at rest,
 *  fading in ghosted on row hover and to full on its own hover (opacity-only). */
export const paletteButton = style([
  accessoryButton,
  {
    opacity: 0,
    transition: `opacity ${duration.fast} ${easing.standard}, background ${duration.fast} ${easing.standard}`,
    selectors: {
      [`${optionRow}:hover &`]: { opacity: 'var(--state-ghost)' },
      [`${optionRow}:hover &:hover`]: { opacity: 1, background: COLOR.iconHover }
    }
  }
])

// ═══════════════════════════════════════════════════════════════════════════
// § LINK EDITOR — the URL property's display config: two toggles + a color chip
// (clicking the chip opens the recolor picker)
// ═══════════════════════════════════════════════════════════════════════════

/** The link config body. The editor root also scopes `--accent` (inline) to the chosen link colour,
 *  so the Switches' on-track tints to it — this pane only (Nathan's neat thing). */
export const linkEditor = style({
  display: 'flex',
  flexDirection: 'column',
  gap: '8px',
  paddingTop: `${OPTION.gapAroundLabel}px`
})

/** One config row — label left, control right. */
export const linkRow = style({ display: 'flex', alignItems: 'center', justifyContent: 'space-between', minHeight: '24px' })

/** The row label (Underline · Full URL · Color) — emphasized (Nathan's call), the primary label tone. */
export const linkLabel = style([text.control.emphasized, { color: c.label.control }])

/** The Switch at pane density — shrunk to sit level with the emphasized labels + colour chip (the same
 *  0.8 the CalendarPicker uses for its picker-scale Switches). Zoom is the house density knob. */
export const switchScale = style({ zoom: 0.8 })

/** The colour control cluster — the clickable chip; the ColorPicker anchors below. */
export const linkColor = style({ position: 'relative', display: 'flex', alignItems: 'center', gap: '4px' })

/** The bare button wrapping the colour chip — the recolor affordance (click the chip to open the picker). */
export const linkChip = style({ border: 'none', background: 'none', padding: 0, cursor: 'default', display: 'flex' })
