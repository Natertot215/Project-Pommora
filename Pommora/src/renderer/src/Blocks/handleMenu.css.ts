import { style } from '@vanilla-extract/css'
import { vars as colorVars } from '../design-system/tokens/color.css'
import { font } from '../design-system/tokens/typography.css'

const c = colorVars.color

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
