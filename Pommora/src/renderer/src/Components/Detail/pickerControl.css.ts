import { style } from '@vanilla-extract/css'
import { vars as colorVars } from '../../design-system/tokens/color.css'
import { text } from '../../design-system/tokens/typography.css'

const c = colorVars.color

/** The picker trigger — bare button reading in the secondary tone; `&&` beats the toolbar/UA button tone. */
export const trigger = style({
  display: 'inline-flex',
  alignItems: 'center',
  gap: '4px',
  border: 'none',
  background: 'none',
  padding: 0,
  cursor: 'default',
  selectors: { '&&': { color: c.label.secondary } },
})

export const value = style([
  text.control.standard,
  { selectors: { '&&': { color: c.label.secondary } } },
])

/** An icon-bearing option row — leading glyph + label, LEFT-aligned (the option's own centering
 *  yields to the row layout when a glyph leads). */
export const iconOption = style({
  display: 'flex',
  alignItems: 'center',
  gap: '6px',
  width: '100%',
  justifyContent: 'flex-start',
})
