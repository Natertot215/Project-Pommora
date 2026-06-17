import { style, styleVariants } from '@vanilla-extract/css'
import { vars as colorVars } from './color.css'
import { text } from './typography.css'

const solid = colorVars.color.solid
const labelPrimary = colorVars.color.label.primary

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

/**
 * The unified chip tint — one formula applied per base color:
 *   fill = base @ 60%  ·  stroke = base @ 40%  ·  text = label-primary + base @ 15%.
 * `color-mix(… X%, transparent)` = the base at X% alpha; the text mixes 15% base
 * into label-primary (matching Figma's Tint/Quinary 15% wash over the label).
 */
const tint = (base: string): { background: string; borderColor: string; color: string } => ({
  background: `color-mix(in srgb, ${base} 60%, transparent)`,
  borderColor: `color-mix(in srgb, ${base} 40%, transparent)`,
  color: `color-mix(in srgb, ${base} 15%, ${labelPrimary})`
})

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
