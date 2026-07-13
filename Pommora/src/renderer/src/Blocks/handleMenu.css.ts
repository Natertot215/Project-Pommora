import { style } from '@vanilla-extract/css'
import { vars as colorVars } from '../design-system/tokens/color.css'
import { font, truncateHoverScroll } from '../design-system/tokens/typography.css'
import { footingLabel } from '../design-system/components/menu/menu.css'

const c = colorVars.color

// ── KNOB — the picker's ONE pane width. The slider viewport follows the active slot's
// measured width, so unequal panes would shift the anchored picker on every slide;
// locking every pane to one width kills the shift and sets the menu's footprint.
export const PANE_W = 120
// The stretch ceiling — a pane may grow to fit content up to this, then labels truncate.
export const PANE_MAX_W = 180

export const pane = style({ minWidth: PANE_W, maxWidth: PANE_MAX_W, boxSizing: 'border-box' })

/** Handle-menu rows read at control size in the control label tone (Nathan's call) —
 *  the && doubles specificity over MenuItem's own class. */
export const row = style({
  selectors: {
    '&&': {
      fontSize: font.scale.control.size,
      lineHeight: font.scale.control.line,
      color: c.label.control
    }
  }
})

/** A structurally-present but inert row (a view embed's Source — sources are per-view, G-14). */
export const rowDisabled = style({
  selectors: {
    '&&': { opacity: 0.4, pointerEvents: 'none' }
  }
})


// ── KNOB — the picker's height ceiling: a drill list grows to this, then its body
// scrolls (MenuScrollFrame owns the cap; header + footer stay pinned).
export const PICKER_MAX_H = 240

/** Header/footer density for this thin menu — the house zoom knob scales the whole bar
 *  (Nathan's call: the scaled bars read right here; tones stay the house classes). */
export const barScale = style({ zoom: 0.85 })

/** A pinned-footer text action (+ Custom) — footing tone over the accessory hover pill. */
export const footerAction = style([
  footingLabel,
  {
    border: 'none',
    background: 'none',
    padding: '2px 4px',
    borderRadius: '5px',
    cursor: 'default',
    selectors: { '&:hover': { background: colorVars.color.state.hover } }
  }
])

/** The footing lock action — a left-pinned labeled toggle (lock icon + "Lock"/"Unlock"): label-secondary
 *  text (footerAction), a step-quieter label-tertiary icon, and the footerAction hover. No pressed/
 *  selected state — it never mutes on lock (only the actions above do). */
export const footerLockAction = style([footerAction, { display: 'inline-flex', alignItems: 'center', gap: '5px' }])
export const lockIcon = style({ selectors: { '&&': { color: c.label.tertiary } } })

/** The page-embed title field (G-16) — the source page's identity as a bordered "field" reading like an
 *  input but acting as a link: clicking it opens the page full-view. A segment hairline (no divider below
 *  it), a two-tier stack (page title over its location), and tight vertical rhythm. `textAlign: left`
 *  undoes the button's default centering; both labels ride the shared ellipsis-at-rest / scroll-on-hover
 *  mechanic. */
export const titleField = style({
  display: 'flex',
  flexDirection: 'column',
  gap: '1px',
  width: '100%',
  boxSizing: 'border-box',
  margin: '0 0 3px',
  padding: '3px 6px',
  border: `1px solid ${c.separator.segment}`,
  borderRadius: '5px',
  background: 'none',
  textAlign: 'left',
  cursor: 'pointer',
  overflow: 'hidden',
  selectors: { '&:hover': { background: c.state.hover } }
})
export const titleFieldRow = style({ display: 'flex', alignItems: 'center', gap: '6px', overflow: 'hidden' })
/** Page title — control type + tone, matching the menu's rows (truncateHoverScroll caps long titles). */
export const titleFieldText = style([
  truncateHoverScroll,
  { flex: 1, minWidth: 0, fontSize: font.scale.control.size, lineHeight: font.scale.control.line, color: c.label.control }
])
/** Location sub-line — footnote (a step under the title), label-secondary. */
export const titleFieldLoc = style([
  truncateHoverScroll,
  { flex: 1, minWidth: 0, fontSize: font.scale.footnote.size, lineHeight: font.scale.footnote.line, color: c.label.secondary }
])
export const titleFieldIcon = style({ selectors: { '&&': { color: c.label.secondary } } })
export const titleFieldLocIcon = style({ selectors: { '&&': { color: c.label.tertiary } } })

/** The Scale dropdown body — a tight column of the five step rows (narrower than the menu's own pane). */
export const scaleMenu = style({ minWidth: 58 })

/** The current step's check, in the runtime accent (not the row's label tone). */
export const scaleCheck = style({ selectors: { '&&': { color: 'var(--accent)' } } })

/** The Scale row's trailing value + double-chevron trigger — a bare button: the current factor in
 *  footnote/label-secondary (mirroring titleFieldLoc), the chevron a step quieter in label-tertiary. */
export const scaleTrailing = style({
  display: 'inline-flex',
  alignItems: 'center',
  gap: '2px',
  padding: 0,
  border: 'none',
  background: 'none',
  cursor: 'default',
  color: c.label.tertiary
})
export const scaleValue = style({
  fontSize: font.scale.footnote.size,
  lineHeight: font.scale.footnote.line,
  color: c.label.secondary
})
