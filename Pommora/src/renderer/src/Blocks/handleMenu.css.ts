import { style } from '@vanilla-extract/css'
import { vars as colorVars } from '../design-system/tokens/color.css'
import { font } from '../design-system/tokens/typography.css'
import { footingLabel } from '../design-system/components/menu/menu.css'

const c = colorVars.color

// ── KNOB — the picker's ONE pane width. The slider viewport follows the active slot's
// measured width, so unequal panes would shift the anchored picker on every slide;
// locking every pane to one width kills the shift and sets the menu's footprint.
export const PANE_W = 120
// The stretch ceiling — a pane may grow to fit content up to this, then labels truncate.
export const PANE_MAX_W = 220

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
export const PICKER_MAX_H = 280

/** Header/footer density for this thin menu — the house zoom knob scales the whole bar. */
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
