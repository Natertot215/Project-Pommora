import { style } from '@vanilla-extract/css'
import { vars as colorVars } from '../../tokens/color.css'

const c = colorVars.color

export const anchor = style({
  position: 'absolute',
  top: 'calc(100% + 6px)',
  left: '50%',
  transform: 'translateX(-50%)',
  zIndex: 20
})

// GlassPane's rect border/shadow are suppressed by NotchedPane (can't trace the beak); the top
// gutter clears the beak band via the shell's published --notch-h.
export const surface = style({
  position: 'relative',
  zIndex: 0,
  padding: '0 6px 6px',
  paddingTop: 'calc(var(--notch-h, 0px) + 6px)',
  display: 'flex',
  flexDirection: 'column',
  gap: '2px'
})

export const option = style({
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  padding: '3px 4px',
  border: 'none',
  background: 'none',
  borderRadius: '8px',
  cursor: 'default',
  selectors: { '&:hover': { background: c.state.hover } }
})

export const optionSelected = style({
  background: c.state.selected,
  selectors: { '&:hover': { background: c.state.selected } }
})
