import { vars as colorVars } from './color.css'
import { font, text } from './typography.css'

/**
 * The single token object. Read scalar values as `vars.color.*` and
 * `vars.font.*` (e.g. `vars.color.solid.blue`, `vars.font.weight.semibold`,
 * `vars.font.scale.body.size`). One import everywhere:
 *   import { vars, text } from '@renderer/design/tokens'
 */
export const vars = {
  ...colorVars,
  font
}

/**
 * Composed text-style class names — apply a whole ramp style:
 *   className={text.body.standard}   ·   className={text.headline.emphasized}
 */
export { text }
