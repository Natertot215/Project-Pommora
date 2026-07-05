import { style } from '@vanilla-extract/css'
import { vars as colorVars, inputFieldVar } from '../tokens/color.css'
import { text } from '../tokens/typography.css'

const c = colorVars.color

/** The fill-quinary, rounded input surface. */
export const field = style([
  text.body.standard,
  {
    display: 'flex',
    alignItems: 'center',
    minHeight: '28px',
    padding: '4px 8px',
    borderRadius: '8px',
    background: inputFieldVar,
    color: c.label.primary,
    width: '100%',
    boxSizing: 'border-box'
  }
])

/** The bare <input> variant — identical chrome, no native border/outline, no focus ring (Nathan:
 *  no focus animation). */
export const input = style([
  field,
  {
    border: 'none',
    outline: 'none',
    font: 'inherit',
    selectors: { '&:focus, &:focus-visible': { outline: 'none', boxShadow: 'none' } }
  }
])
