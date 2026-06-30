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

export const pop = style({ position: 'relative', width: 'fit-content' })

// GlassPane's rect border/shadow are suppressed (can't trace the beak); the frame SVG draws the outline.
export const surface = style({
  position: 'relative',
  zIndex: 0,
  padding: '0 6px 6px',
  display: 'flex',
  flexDirection: 'column',
  gap: '2px'
})

// SVG stroke of the same notch path — a rect box-shadow can't follow the beak.
export const frame = style({
  position: 'absolute',
  inset: 0,
  overflow: 'visible',
  pointerEvents: 'none',
  zIndex: 1,
  filter: 'drop-shadow(0 4px 14px #00000059)'
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
