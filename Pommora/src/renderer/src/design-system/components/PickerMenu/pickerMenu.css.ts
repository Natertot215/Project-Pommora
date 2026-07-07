import { style } from '@vanilla-extract/css'
import { vars as colorVars } from '../../tokens/color.css'
import { text } from '../../tokens/typography.css'

const c = colorVars.color

export const anchor = style({
  position: 'absolute',
  top: 'calc(100% + 6px)',
  left: '50%',
  transform: 'translateX(-50%)',
  zIndex: 20
})
/** Upward-opening variant — the pane hangs ABOVE its trigger (beak-down NotchedPane). */
export const anchorUp = style({
  position: 'absolute',
  bottom: 'calc(100% + 6px)',
  left: '50%',
  transform: 'translateX(-50%)',
  zIndex: 20
})
/** The self-managed top layer — a fixed body-portal position (set inline from the measured trigger)
 *  so the pane escapes any clipping ancestor (the settings dropdown's frost clip). */
export const layer = style({ position: 'fixed', zIndex: 100 })

/** A transparent full-viewport catcher one layer BELOW the pane: any outside pointerdown (including
 *  on the trigger itself) lands here and dismisses, so the trigger's own click can't reopen. */
export const backdrop = style({ position: 'fixed', inset: 0, zIndex: 99 })

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
/** Beak-down twin: the notch band moves to the bottom gutter. Composed after `surface` so its
 *  padding wins. */
export const surfaceUp = style({
  paddingTop: '6px',
  paddingBottom: 'calc(var(--notch-h, 0px) + 6px)'
})

// The portal escapes any label-tone context, so the option must set its OWN type + colour (else it
// falls to the UA default — black, unsized — and the pane wraps). Matches a dropdown row title: the
// control scale at the control tone.
export const option = style([
  text.control.standard,
  {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    whiteSpace: 'nowrap',
    padding: '3px 4px',
    border: 'none',
    background: 'none',
    borderRadius: '8px',
    color: c.label.control,
    cursor: 'default',
    selectors: { '&:hover': { background: c.state.hover } }
  }
])

export const optionSelected = style({
  background: c.state.selected,
  selectors: { '&:hover': { background: c.state.selected } }
})
