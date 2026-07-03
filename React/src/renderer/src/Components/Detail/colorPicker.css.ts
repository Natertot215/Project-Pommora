import { style, styleVariants } from '@vanilla-extract/css'
import { vars as colorVars } from '../../design-system/tokens/color.css'

const solid = colorVars.color.solid

/** The 2×5 swatch grid — 16px swatches, 4px gaps, inside the PickerMenu shell's own padding. */
export const grid = style({
  display: 'grid',
  gridTemplateColumns: 'repeat(2, 16px)',
  gap: '4px'
})

/** Each swatch publishes its solid as `--sw`, so the fill and the selected ring share one source
 *  (the ring reads in the swatch's OWN colour — Nathan's call). DRY'd off the shared colour tokens,
 *  so a new palette entry drops straight in. */
export const swatchColor = styleVariants({
  red: { vars: { '--sw': solid.red } },
  orange: { vars: { '--sw': solid.orange } },
  yellow: { vars: { '--sw': solid.yellow } },
  green: { vars: { '--sw': solid.green } },
  lightBlue: { vars: { '--sw': solid.lightBlue } },
  cyan: { vars: { '--sw': solid.cyan } },
  blue: { vars: { '--sw': solid.blue } },
  purple: { vars: { '--sw': solid.purple } },
  lavender: { vars: { '--sw': solid.lavender } },
  grey: { vars: { '--sw': solid.grey } }
})

export const swatch = style({
  width: '16px',
  height: '16px',
  borderRadius: '3px',
  border: 'none',
  padding: 0,
  cursor: 'default',
  background: 'var(--sw)'
})
