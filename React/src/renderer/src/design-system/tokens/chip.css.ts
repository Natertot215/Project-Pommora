import { style, styleVariants } from '@vanilla-extract/css'
import { vars as colorVars } from './color.css'
import { text } from './typography.css'
import { tint } from './tint'

const solid = colorVars.color.solid

/**
 * Base chip — layout + a 2px stroke, composing the Control / Emphasized text
 * style (the one source for that ramp — never re-state size / line / weight).
 * Color is supplied by `chipColor.*`; shape via `chipCheckbox`. Compose:
 * `${chip} ${chipColor.blue}`.
 */
export const chip = style([
  text.control.emphasized,
  {
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: '4px',
    boxSizing: 'border-box',
    height: '20px',
    padding: '0 6px',
    borderRadius: '10px',
    borderStyle: 'solid',
    borderWidth: '2px',
    whiteSpace: 'nowrap'
  }
])

/** One class per spectrum color — compose with `chip`. Mirrors the 11 Figma chip color variants. */
export const chipColor = styleVariants({
  red: tint(solid.red),
  blue: tint(solid.blue),
  green: tint(solid.green),
  purple: tint(solid.purple),
  lavender: tint(solid.lavender),
  cyan: tint(solid.cyan),
  lightBlue: tint(solid.lightBlue),
  orange: tint(solid.orange),
  yellow: tint(solid.yellow),
  grey: tint(solid.grey),
  default: tint(solid.greyDefault)
})

/**
 * Checkbox chip — a fixed 17×17 rounded square (radius 5.5) with a 1.5px stroke;
 * holds only a checkmark. Pill = a text `chip`; Select = a `chip` with an icon
 * (both are pills — no shape modifier needed).
 */
export const chipCheckbox = style({
  width: '17px',
  height: '17px',
  padding: 0,
  borderRadius: '5.5px',
  borderWidth: '1.5px'
})
