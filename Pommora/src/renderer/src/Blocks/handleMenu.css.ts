import { style } from '@vanilla-extract/css'
import { vars as colorVars } from '../design-system/tokens/color.css'
import { font } from '../design-system/tokens/typography.css'

const c = colorVars.color

// ── KNOB — the picker's ONE pane width. The slider viewport follows the active slot's
// measured width, so unequal panes would shift the anchored picker on every slide;
// locking every pane to one width kills the shift and sets the menu's footprint.
export const PANE_W = 132

export const pane = style({ width: PANE_W, boxSizing: 'border-box' })

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
