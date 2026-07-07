import { style } from '@vanilla-extract/css'
import { vars } from '../../tokens/color.css'

/** The unfilled track — a thin rounded bar in the label-control fill. No stroke (held for Nathan's eyeball). */
export const track = style({
  width: '100%',
  height: '6px',
  borderRadius: '999px',
  background: vars.color.label.control,
  overflow: 'hidden'
})

/** The filled portion — the runtime accent, width-driven. */
export const fill = style({
  height: '100%',
  borderRadius: '999px',
  background: 'var(--accent)'
})
