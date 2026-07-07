import { vars as colorVars } from '@renderer/design-system/tokens/color.css'
import { chipColorFor } from '@renderer/design-system/tokens/colorMap'

const SOLIDS = colorVars.color.solid

/** The CSS colour a palette key resolves to: its stored solid, or the runtime system accent when
 *  unset ("Default"). One source for the link cell/editor AND the checkbox cell/editor. */
export function solidColorCss(color: string | undefined): string {
  if (!color) return 'var(--system-accent)'
  const key = chipColorFor(color)
  return key === 'default' ? SOLIDS.greyDefault : (SOLIDS as Record<string, string>)[key]
}
