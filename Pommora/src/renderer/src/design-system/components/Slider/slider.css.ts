import { style } from '@vanilla-extract/css'

/** The slider's hit strip — hosts the ProgressBar track + the glass knob riding over it. */
export const strip = style({
  position: 'relative',
  display: 'flex',
  alignItems: 'center',
  flex: 1,
  minWidth: 0,
  padding: '6px 0',
  touchAction: 'none',
})

/** The knob — sized + centered here; its glass is the shared frostMaterial recipe, applied inline. */
export const knob = style({
  position: 'absolute',
  width: 14,
  height: 14,
  borderRadius: '999px',
  transform: 'translateX(-50%)',
  pointerEvents: 'none',
})
