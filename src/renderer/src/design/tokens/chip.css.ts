import { style, styleVariants } from '@vanilla-extract/css'
import { vars as colorVars } from './color.css'
import { font } from './typography.css'

const solid = colorVars.color.solid
const labelPrimary = colorVars.color.label.primary

/**
 * Base chip — layout, a 2px stroke, and Control / Emphasized type. Color is
 * supplied by `chipColor.*`; adjust shape/stroke with `chipSquare` /
 * `chipCheckbox`. Compose: `${chip} ${chipColor.blue}`.
 */
export const chip = style({
  display: 'inline-flex',
  alignItems: 'center',
  gap: '4px',
  boxSizing: 'border-box',
  padding: '2px 10px',
  borderRadius: '999px',
  borderStyle: 'solid',
  borderWidth: '2px',
  whiteSpace: 'nowrap',
  fontFamily: font.family,
  fontSize: font.scale.control.size,
  lineHeight: font.scale.control.line,
  fontWeight: font.weight.semibold,
  letterSpacing: 0
})

/**
 * The unified chip tint — one formula applied per base color:
 *   fill = base @ 60%  ·  stroke = base @ 40%  ·  text = label-primary + base @ 10%.
 * `color-mix(… X%, transparent)` = the base at X% alpha; the text mixes 10% base
 * into label-primary (matching the Figma label-primary + base-10% stack).
 */
const tint = (base: string): { background: string; borderColor: string; color: string } => ({
  background: `color-mix(in srgb, ${base} 60%, transparent)`,
  borderColor: `color-mix(in srgb, ${base} 40%, transparent)`,
  color: `color-mix(in srgb, ${base} 10%, ${labelPrimary})`
})

/** One class per chip color — compose with `chip`. No red (excluded by design). */
export const chipColor = styleVariants({
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

/** Square / Select shape — rounded-rect instead of a pill. */
export const chipSquare = style({ borderRadius: '7px' })

/** Checkbox chip — thinner 1.5px stroke (per spec). */
export const chipCheckbox = style({ borderWidth: '1.5px' })
