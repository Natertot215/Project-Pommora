import { style } from '@vanilla-extract/css'

export const pop = style({ position: 'relative', width: 'fit-content' })

// SVG stroke of the same notch path — a rect box-shadow can't follow the beak, so the frame
// carries the pane's shadow as a drop-shadow too.
export const frame = style({
  position: 'absolute',
  inset: 0,
  overflow: 'visible',
  pointerEvents: 'none',
  zIndex: 1,
  filter: 'drop-shadow(0 4px 14px #00000059)',
})
