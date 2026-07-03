import { globalStyle, keyframes, style } from '@vanilla-extract/css'
import { vars } from '../../tokens/color.css'
import { duration, easing } from '../../tokens/motion'
import { TINT_STEPS, tintAt } from '../../tokens/tint'
import { font } from '../../tokens/typography.css'

const c = vars.color
// Selection tints (Nathan's ratified pair): endpoints at tint-secondary, the in-between band a
// step lighter at tint-tertiary — both off the live --accent.
const endpointFill = tintAt('var(--accent)', TINT_STEPS.secondary)
const bandFill = tintAt('var(--accent)', TINT_STEPS.tertiary)

/* The picker's intrinsic width — the PickerMenu pane shrink-wraps this (+ its gutters). THE
   sizing knob; everything inside flows from it. textAlign resets the host's inheritance — a
   picker mounted inside a <button> trigger would otherwise center every label. */
export const root = style({ width: '216px', textAlign: 'left' })

/* Content size changes (toggles, month row-count) ride the same beat as PaneSlider's viewport —
   the ViewPane feel: measured height, transition armed only after first paint so the pane opens
   at size instead of growing from 0. */
export const morph = style({ overflow: 'hidden' })
export const morphAnimated = style({ transition: `height ${duration.base} ${easing.standard}` })

/* ── Header: [Month] [Year] (label-control buttons, each opening its own selection dropdown)
      + ‹ | › nav with a segment bar between the chevrons ── */
export const head = style({ display: 'flex', alignItems: 'center', padding: '2px 4px 6px' })
export const headDivider = style({ height: '1px', background: c.separator.line, margin: '0 2px 6px' })
export const titleGroup = style({ flex: 1, display: 'flex', gap: '5px' })
export const titleBtn = style({
  all: 'unset',
  position: 'relative',
  fontSize: font.scale.body.size,
  fontWeight: font.weight.semibold,
  color: c.label.control,
  selectors: { '&:hover': { color: c.label.primary } }
})
/* translateY nudges the chevron cluster up without costing the row any height. */
export const nav = style({ display: 'flex', alignItems: 'center', gap: '2px', transform: 'translateY(-2px)' })
export const navSegment = style({ width: '1px', height: '12px', background: c.separator.segment })
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

/* ── Month / Year selection dropdowns: the option list inside a nested PickerMenu; the year list
      shows ~10 rows before it scrolls. The wrapper left-anchors the nested pane (PickerMenu
      centers by default, which pushed it past the calendar pane's clip edge) and lifts it ABOVE
      the calendar content. ── */
export const ddWrap = style({ display: 'contents' })
globalStyle(`${ddWrap} > div`, { left: 0, transform: 'none', zIndex: 30 })
export const menuList = style({
  display: 'flex',
  flexDirection: 'column',
  gap: '2px',
  minWidth: '110px',
  maxHeight: '136px', // ≈6 option rows before it over-scrolls (rides the shared scroll-edge-fade)
  overflowY: 'auto',
  scrollbarWidth: 'none',
  selectors: { '&::-webkit-scrollbar': { display: 'none' } }
})
/* Option rows: left-aligned label-control text; the selected row shows an accent check at its
   right edge. */
export const optionRow = style({
  flex: 1,
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between',
  gap: '8px',
  textAlign: 'left',
  fontSize: font.scale.body.size, // the pane's own scale (matches the Month/Year title)
  color: c.label.control
})
export const optionCheck = style({ flex: 'none', color: 'var(--accent)' })

/* ── Week headings: Mon…Sun, label-secondary ── */
export const weekRow = style({ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', padding: '0 2px' })
export const weekday = style({
  textAlign: 'center',
  fontSize: font.scale.footnote.size,
  fontWeight: font.weight.semibold,
  letterSpacing: '0.02em',
  color: c.label.secondary,
  padding: '3px 0 5px'
})

/* ── Month grid + the duration-base ‹ › slide ── */
const slideLeft = keyframes({ from: { transform: 'translateX(0)' }, to: { transform: 'translateX(-50%)' } })
const slideRight = keyframes({ from: { transform: 'translateX(-50%)' }, to: { transform: 'translateX(0)' } })
export const viewport = style({ overflow: 'hidden' })
/* Top-aligned so each month grid keeps its own height — the viewport's computed height (not the
   taller neighbor) decides the pane, and SizeMorph animates the change WITH the slide (one beat,
   the PaneSlider contract: the horizontal move and the resize land together). */
export const track = style({ display: 'flex', width: '200%', alignItems: 'flex-start' })
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
  fontSize: font.scale.caption.size,
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
export const daySelected = style({ fontWeight: font.weight.semibold })
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
  padding: '4px 7px',
  background: c.fill.tertiary // ad-hoc fill on this surface — Nathan's call
})
export const fieldIcon = style({ flex: 'none', color: c.label.secondary })
export const fieldValue = style({
  flex: 1,
  minWidth: 0,
  textAlign: 'center',
  fontSize: font.scale.control.size,
  fontWeight: font.weight.emphasized,
  color: c.label.primary
})
export const fieldEmpty = style({ color: c.label.tertiary })
/* The date+time row splits ~2/3 : 1/3 (Nathan's layout; shaded 1.8:1.2 so the segment cluster
   fits its box — THE ratio knob); plain rows share evenly. */
export const fieldGrow = style({ flex: 1.8 })
export const fieldTime = style({ flex: 1.2, gap: '4px', paddingLeft: '6px', paddingRight: '6px' })
/* The [00][00] time segments — each is a dropdown trigger; its menu opens upward, beak-down. */
export const timeSegs = style({ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '2px' })
export const timeSeg = style({
  all: 'unset',
  position: 'relative',
  padding: '1px 4px',
  borderRadius: '5px',
  fontSize: font.scale.control.size,
  fontWeight: font.weight.emphasized,
  color: c.label.primary,
  selectors: { '&:hover': { background: c.state.hover } }
})
export const timeColon = style({ color: c.label.secondary })

/* ── Boolean rows (the real Switch) ── */
export const switchRow = style({
  display: 'flex',
  alignItems: 'center',
  minHeight: '28px',
  padding: '0 2px'
})
export const switchLabel = style({
  flex: 1,
  fontSize: font.scale.control.size,
  fontWeight: font.weight.emphasized,
  color: c.label.control
})
/* The real Switch at picker scale — zoom is the house density knob (the table uses the same). */
export const switchScale = style({ zoom: 0.8 })

/* ── Homepage demo chrome (dev mount): a fake value-chip trigger; the real PickerMenu pane hangs
      under it (absolute), so the cell reserves the pane's height. ── */
export const demoRow = style({ display: 'flex', gap: '40px', flexWrap: 'wrap', alignItems: 'flex-start' })
export const demoCell = style({
  position: 'relative',
  display: 'flex',
  flexDirection: 'column',
  gap: '8px',
  alignItems: 'flex-start',
  width: '280px',
  minHeight: '480px'
})
export const demoTag = style({ fontSize: font.scale.control.size, color: c.label.secondary })
export const demoTrigger = style({
  position: 'relative',
  border: `1px solid ${c.separator.line}`,
  borderRadius: '6px',
  padding: '3px 10px',
  fontSize: font.scale.control.size,
  color: c.label.primary,
  background: c.state.hover
})
