import { style } from '@vanilla-extract/css'
import { vars as colorVars } from '../../tokens/color.css'
import { tintAt, TINT_STEPS } from '../../tokens/tint'
import { duration, easing } from '../../tokens/motion'

const c = colorVars.color
const ease = `${duration.fast} ${easing.standard}` // one motion source for the whole switch
const control = 'var(--label-control)' // knob fill + tick glyphs — the global on-control label token

/**
 * The Figma "Switch" — a 54×24 pill sliding a liquid-glass knob between a `|` (on) and an `O` (off)
 * tick. Geometry mirrors the Figma component (track 54×24, knob inset 2 → 28×20, full pills). The knob
 * is the label-control white fill wrapped in the real liquid glass (GlassControls); off-fill quinary,
 * on-fill accent + tint-primary, behind a label-secondary stroke.
 */
export const track = style({
  position: 'relative',
  width: '54px',
  height: '24px',
  borderRadius: '12px',
  border: '1px solid var(--label-secondary)',
  background: c.fill.quinary,
  padding: 0,
  flex: '0 0 auto',
  cursor: 'default',
  transition: `background ${ease}`
})

export const trackOn = style({ background: tintAt('var(--accent)', TINT_STEPS.primary) })

// The sliding slot — vertically centred (top 50% / translateY) so the 1px border never offsets it; it
// shrink-wraps the glass-wrapped fill and slides 22px between off (left) and on (right).
export const knob = style({
  position: 'absolute',
  top: '50%',
  left: '2px', // 3px visual inset from the track edge (1px border + 2px)
  display: 'flex', // drops the inline-block baseline descender so translateY centres the glass exactly
  transform: 'translateY(-50%)',
  transition: `transform ${ease}`,
  selectors: { [`${trackOn} &`]: { transform: 'translate(22px, -50%)' } }
})

export const knobFill = style({
  display: 'block',
  width: '26px',
  height: '18px',
  borderRadius: '9px',
  background: control
})

// Both ticks: centred, label-control, fade on the same beat as the slide; one shows per state.
const tickBase = style({
  position: 'absolute',
  top: '50%',
  borderRadius: '100px',
  transition: `opacity ${ease}`
})

export const tickLine = style([
  tickBase,
  {
    left: '13px',
    transform: 'translate(-50%, -50%)',
    width: '2px',
    height: '10px',
    background: control,
    opacity: 0,
    selectors: { [`${trackOn} &`]: { opacity: 1 } }
  }
])

export const tickCircle = style([
  tickBase,
  {
    right: '10px',
    transform: 'translateY(-50%)',
    width: '6px',
    height: '6px',
    border: `1.5px solid ${control}`,
    opacity: 1,
    selectors: { [`${trackOn} &`]: { opacity: 0 } }
  }
])

export const disabled = style({ opacity: 0.4 })
