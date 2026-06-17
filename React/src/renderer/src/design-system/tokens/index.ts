import { vars as colorVars } from './color.css'
import { font, text } from './typography.css'
import { chip, chipColor, chipCheckbox, tint } from './chip.css'
import './theme-vars.css' // bridges tokens → stable CSS vars for plain-CSS consumers

/**
 * The single token object. Read scalar values as `vars.color.*` and
 * `vars.font.*` (e.g. `vars.color.solid.blue`, `vars.color.label.primary`,
 * `vars.font.weight.semibold`, `vars.font.scale.body.size`). One import:
 *   import { vars, text, chip, chipColor } from '@renderer/design-system/tokens'
 */
export const vars = {
  ...colorVars,
  font
}

/** Composed text-style class names — `text.body.standard`, `text.headline.emphasized`. */
export { text }

/**
 * Chip recipe — the unified tint (fill = base 60% · stroke = base 40%, 2px /
 * 1.5px checkbox · text = label-primary + base 15%). Compose
 * `${chip} ${chipColor.blue}`; add `chipCheckbox` for the 17×17 checkbox square.
 * A plain `chip` is a Pill (text) or Select (icon). `tint(base)` is the raw recipe
 * (e.g. for an accent chip via `tint('var(--accent)')`). See chip.css.ts.
 */
export { chip, chipColor, chipCheckbox, tint }
