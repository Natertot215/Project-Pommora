import { vars as colorVars } from './color.css'
import { font, text } from './typography.css'
import {
  chipPill,
  chipLabel,
  chipContext,
  chipCapsule,
  chipBox,
  chipBoxGeometry,
  chipColor,
  chipLabelWrap,
  chipLabelText,
  chipLabelBlur,
  chipLabelMelt,
  chipRemovable,
  chipRemove,
} from './chip.css'
import { size, type IconSize, type ButtonSize } from './size.css'
import { tint, tintAt, TINT_STEPS, type TintStep } from './tint'
import './theme-vars.css' // bridges tokens → stable CSS vars for plain-CSS consumers

/**
 * The single token object. Read scalar values as `vars.color.*`, `vars.font.*`,
 * and `vars.size.*` (e.g. `vars.color.solid.blue`, `vars.font.weight.semibold`,
 * `vars.size.icon.md`, `vars.size.control.button.large.height`). One import:
 *   import { vars, text, chipPill, chipColor } from '@renderer/design-system/tokens'
 */
export const vars = {
  ...colorVars,
  font,
  size,
}

/** Size aliases — `IconSize` for `<Icon size>`, `ButtonSize` for a control's `size`. */
export type { IconSize, ButtonSize }

/** Composed text-style class names — `text.body.standard`, `text.headline.emphasized`. */
export { text }

/**
 * Chip primitives — one class per SHAPE, composed with one `chipColor.*`:
 * `${chipPill} ${chipColor.blue}` (status text) · `chipLabel` (select/multi, 6px
 * radius) · `chipContext` (context/tier) · `chipCapsule` (icon-only) · `chipBox`
 * (the 17×17 rounded square). The unified tint: fill = base 60% ·
 * stroke = base 40% · text = label-primary + base 15%. `tint(base)` is the
 * raw recipe (e.g. an accent chip via `tint('var(--accent)')`). See chip.css.ts.
 */
export {
  chipPill,
  chipLabel,
  chipContext,
  chipCapsule,
  chipBox,
  chipBoxGeometry,
  chipColor,
  chipLabelWrap,
  chipLabelText,
  chipLabelBlur,
  chipLabelMelt,
  chipRemovable,
  chipRemove,
  tint,
  tintAt,
  TINT_STEPS,
}
export type { TintStep }
export { duration, easing } from './motion'
