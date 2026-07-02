import { vars as colorVars } from './color.css'
import { font, text } from './typography.css'
import { chip, chipColor, chipCheckbox, chipCapsule, chipLabel, chipRemovable, chipRemove, chipFrost } from './chip.css'
import { size, type IconSize, type ButtonSize } from './size.css'
import { tint, tintAt, TINT_STEPS, type TintStep } from './tint'
import './theme-vars.css' // bridges tokens → stable CSS vars for plain-CSS consumers

/**
 * The single token object. Read scalar values as `vars.color.*`, `vars.font.*`,
 * and `vars.size.*` (e.g. `vars.color.solid.blue`, `vars.font.weight.semibold`,
 * `vars.size.icon.md`, `vars.size.control.button.large.height`). One import:
 *   import { vars, text, chip, chipColor } from '@renderer/design-system/tokens'
 */
export const vars = {
  ...colorVars,
  font,
  size
}

/** Size aliases — `IconSize` for `<Icon size>`, `ButtonSize` for a control's `size`. */
export type { IconSize, ButtonSize }

/** Composed text-style class names — `text.body.standard`, `text.headline.emphasized`. */
export { text }

/**
 * Chip recipe — the unified tint (fill = base 60% · stroke = base 40%, 2px /
 * 1.5px checkbox · text = label-primary + base 15%). Compose
 * `${chip} ${chipColor.blue}`; add `chipCheckbox` for the 17×17 checkbox square
 * or `chipCapsule` for the icon-only capsule. A plain `chip` is a Pill (text).
 * `tint(base)` is the raw recipe (e.g. for an accent chip via
 * `tint('var(--accent)')`). See chip.css.ts.
 */
export { chip, chipColor, chipCheckbox, chipCapsule, chipLabel, chipRemovable, chipRemove, chipFrost, tint, tintAt, TINT_STEPS }
export type { TintStep }
export { duration, easing } from './motion'
