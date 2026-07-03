import { keyframes, style } from '@vanilla-extract/css'
import { vars } from '../../tokens/color.css'
import { TINT_STEPS, tintAt } from '../../tokens/tint'

const c = vars.color
// Selection tints (Nathan's ratified pair): endpoints at tint-secondary, the in-between band a
// step lighter at tint-tertiary — both off the live --accent.
const endpointFill = tintAt('var(--accent)', TINT_STEPS.secondary)
const bandFill = tintAt('var(--accent)', TINT_STEPS.tertiary)

/* The picker's intrinsic width — the PickerMenu pane shrink-wraps this (+ its gutters). THE
   sizing knob; everything inside flows from it. */
export const root = style({ width: '216px' })

/* ── Header: Month Year (one color) + ‹ › ── */
export const head = style({ display: 'flex', alignItems: 'center', padding: '2px 4px 8px' })
export const title = style({
  flex: 1,
  fontSize: '13.5px',
  fontWeight: 600,
  color: c.label.primary
})
export const nav = style({ display: 'flex', gap: '2px' })
export const navBtn = style({
  all: 'unset',
  width: '24px',
  height: '22px',
  borderRadius: '6px',
  display: 'grid',
  placeItems: 'center',
  color: c.label.secondary,
  selectors: { '&:hover': { background: c.state.hover, color: c.label.primary } }
})

/* ── Week headings: Mon…Sun, label-secondary ── */
export const weekRow = style({ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', padding: '0 2px' })
export const weekday = style({
  textAlign: 'center',
  fontSize: '10px',
  fontWeight: 600,
  letterSpacing: '0.02em',
  color: c.label.secondary,
  padding: '3px 0 5px'
})

/* ── Month grid + the duration-base ‹ › slide ── */
const slideLeft = keyframes({ from: { transform: 'translateX(0)' }, to: { transform: 'translateX(-50%)' } })
const slideRight = keyframes({ from: { transform: 'translateX(-50%)' }, to: { transform: 'translateX(0)' } })
export const viewport = style({ overflow: 'hidden' })
export const track = style({ display: 'flex', width: '200%' })
export const trackLeft = style({ animation: `${slideLeft} var(--duration-base) var(--ease-standard) both` })
export const trackRight = style({ animation: `${slideRight} var(--duration-base) var(--ease-standard) both` })
export const days = style({
  display: 'grid',
  gridTemplateColumns: 'repeat(7, 1fr)',
  rowGap: '2px',
  padding: '0 2px 2px',
  width: '50%',
  flex: 'none'
})
export const day = style({
  all: 'unset',
  height: '24px',
  textAlign: 'center',
  fontSize: '11.5px',
  display: 'grid',
  placeItems: 'center',
  position: 'relative',
  isolation: 'isolate',
  color: c.label.primary
})
export const dayOut = style({ color: c.label.tertiary })
/* The fill layer under each date. Endpoints square off their inner edge and the band bleeds
   full-width, so a range reads as ONE connected strip, never per-day pills. */
export const pill = style({
  position: 'absolute',
  inset: '1px',
  borderRadius: '7px',
  zIndex: -1,
  selectors: { [`${day}:hover &`]: { background: c.state.hover } }
})
export const pillToday = style({ boxShadow: `inset 0 0 0 1px ${c.label.tertiary}` })
export const pillSelected = style({ background: `${endpointFill} !important` })
export const daySelected = style({ fontWeight: 650 })
/* Range endpoints stay FULLY rounded pills; the tertiary band runs UNDERNEATH them (a half-width
   under-layer toward the range side), so the strip connects while the endpoint keeps both its
   rounded edges overlapping the under-tint. */
export const bandUnderStart = style({ background: `${bandFill} !important`, borderRadius: 0, inset: '1px 0 1px 50%' })
export const bandUnderEnd = style({ background: `${bandFill} !important`, borderRadius: 0, inset: '1px 50% 1px 0' })
export const pillMid = style({ background: `${bandFill} !important`, borderRadius: 0, inset: '1px 0' })
export const pillRowFirst = style({ borderRadius: '7px 0 0 7px', inset: '1px 0 1px 1px' })
export const pillRowLast = style({ borderRadius: '0 7px 7px 0', inset: '1px 1px 1px 0' })

/* ── Divider between the calendar and the value/boolean area ── */
export const divider = style({ height: '1px', background: c.separator.line, margin: '7px 2px 8px' })

/* ── Value fields: separator-stroked inputs, icon + value (or the -- empty). The block keeps
      EQUAL breathing room above (divider's 8px) and below (its own 8px margin). ── */
export const fields = style({ display: 'flex', flexDirection: 'column', gap: '6px', padding: '0 2px', marginBottom: '8px' })
export const fieldRow = style({ display: 'flex', gap: '6px' })
export const field = style({
  flex: 1,
  minWidth: 0,
  display: 'flex',
  alignItems: 'center',
  gap: '6px',
  border: `1px solid ${c.separator.line}`,
  borderRadius: '8px',
  padding: '4px 7px'
})
export const fieldIcon = style({ flex: 'none', color: c.label.secondary })
export const fieldValue = style({ flex: 1, minWidth: 0, fontSize: '12px', color: c.label.primary })
export const fieldEmpty = style({ color: c.label.tertiary })

/* ── Boolean rows (the real Switch) ── */
export const switchRow = style({
  display: 'flex',
  alignItems: 'center',
  minHeight: '28px',
  padding: '0 2px'
})
export const switchLabel = style({ flex: 1, fontSize: '12.5px', color: c.label.primary })

/* ── Homepage demo chrome (dev mount): a fake value-chip trigger; the real PickerMenu pane hangs
      under it (absolute), so the cell reserves the pane's height. ── */
export const demoRow = style({ display: 'flex', gap: '40px', flexWrap: 'wrap', alignItems: 'flex-start' })
export const demoCell = style({
  position: 'relative',
  display: 'flex',
  flexDirection: 'column',
  gap: '8px',
  alignItems: 'flex-start',
  width: '270px',
  minHeight: '480px'
})
export const demoTag = style({ fontSize: '12px', color: c.label.secondary })
export const demoTrigger = style({
  position: 'relative',
  border: `1px solid ${c.separator.line}`,
  borderRadius: '6px',
  padding: '3px 10px',
  fontSize: '12px',
  color: c.label.primary,
  background: c.state.hover
})
