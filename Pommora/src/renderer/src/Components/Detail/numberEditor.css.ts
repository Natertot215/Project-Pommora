import { style } from '@vanilla-extract/css'
import { vars as colorVars } from '../../design-system/tokens/color.css'
import { text } from '../../design-system/tokens/typography.css'

/** The editor body — no flex `gap` (a collapsed Reveal would otherwise consume a phantom gap on each
 *  side, so hidden rows double the spacing around them); each Row carries its own top margin, which
 *  rides inside a Reveal and so collapses to nothing when the row is hidden. */
export const section = style({ display: 'flex', flexDirection: 'column', paddingTop: '6px' })

/** One row's spacing — the inter-row gap, applied per-row so a hidden Reveal contributes none. */
export const row = style({ marginTop: '8px' })

/** The Value control — the value + double-chevron in one box, identical at rest and while editing so the
 *  number never shifts; editing just swaps the static value for an in-place caret. */
export const valueControl = style({
  display: 'inline-flex',
  alignItems: 'center',
  gap: '4px',
  padding: 0,
  border: 'none',
  background: 'none',
  cursor: 'default',
  selectors: { '&&': { color: colorVars.color.label.secondary } }
})

/** The in-place caret — bare, at the value's own control metrics so the caret is sized to the text (not
 *  the UA default), reading in the same secondary tone as the resting value. */
export const valueCaret = style([
  text.control.standard,
  {
    minWidth: '12px',
    width: 'auto',
    fieldSizing: 'content',
    border: 'none',
    outline: 'none',
    padding: 0,
    background: 'transparent',
    color: colorVars.color.label.secondary
  }
])
