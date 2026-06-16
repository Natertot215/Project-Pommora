import { vars as colorVars } from './color.css'
import { font, text } from './typography.css'
import { chip, chipColor, chipSquare, chipCheckbox } from './chip.css'

/**
 * The single token object. Read scalar values as `vars.color.*` and
 * `vars.font.*` (e.g. `vars.color.solid.blue`, `vars.color.label.primary`,
 * `vars.font.weight.semibold`, `vars.font.scale.body.size`). One import:
 *   import { vars, text, chip, chipColor } from '@renderer/design/tokens'
 */
export const vars = {
  ...colorVars,
  font
}

/** Composed text-style class names — `text.body.standard`, `text.headline.emphasized`. */
export { text }

/**
 * Chip recipe — the unified tint (fill = base 60% · stroke = base 40%, 2px /
 * 1.5px checkbox · text = label-primary + base 10%). Compose
 * `${chip} ${chipColor.blue}` (+ `chipSquare` / `chipCheckbox`). See chip.css.ts.
 */
export { chip, chipColor, chipSquare, chipCheckbox }
