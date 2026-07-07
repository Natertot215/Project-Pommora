import { style } from '@vanilla-extract/css'
import { vars as colorVars, inputFieldVar } from '../../design-system/tokens/color.css'
import { text } from '../../design-system/tokens/typography.css'

/** The Value (denominator) numeric input — a small right-aligned field in the config row, the
 *  input-field fill, the control label tone. */
export const valueInput = style([
  text.control.emphasized,
  {
    width: '64px',
    textAlign: 'right',
    background: inputFieldVar,
    border: 'none',
    outline: 'none',
    borderRadius: '6px',
    padding: '2px 6px',
    color: colorVars.color.label.control,
    font: 'inherit'
  }
])
