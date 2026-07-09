// The Grouping pane's row-tier knobs. Primary rows (Group By / Sub-Group / Date By) read the
// MenuItem default (Body, label-primary); a subordinate Order row reads a step quieter and
// tucks toward its parent so the pair reads grouped (C-8).
import { globalStyle, style } from '@vanilla-extract/css'
import { vars as colorVars } from '../../design-system/tokens/color.css'
import { text } from '../../design-system/tokens/typography.css'
import { value as pickerValue } from './pickerControl.css'

const c = colorVars.color

/** KNOB — how far a subordinate Order row tucks toward its parent row. */
const SUB_ORDER_GAP = '-4px'

export const subRow = style({ marginTop: SUB_ORDER_GAP })

export const subLabel = style([text.body.emphasized, { color: c.label.secondary }])

/** KNOB — the hierarchy's disclosed sub-group chips render a step smaller than table chips. */
export const subChip = style({ zoom: 0.85 })

/** KNOB — the rail's x: the parent icon's centre (8px row padding + half the 13px glyph). */
const RAIL_X = '14px'

/** A disclosed child run rides the shared list-outline rail (interactions.css), centred under the
 *  parent's icon with rounded caps; children indent past it. */
export const railRow = style({
  position: 'relative',
  paddingLeft: '20px',
  '::before': {
    content: '""',
    position: 'absolute',
    top: 'var(--list-outline-gap)',
    bottom: 'var(--list-outline-gap)',
    left: `calc(${RAIL_X} - var(--list-outline-width) / 2)`,
    width: 'var(--list-outline-width)',
    borderRadius: 'var(--list-outline-radius)',
    background: 'var(--list-outline-color)'
  }
})

/** The Group By row's trailing value — Control-size (the PickerControl trigger's weight class), a
 *  step LARGER than the menus' Footnote detail so the pane's lead value reads at full strength. */
export const groupByValue = style([
  text.control.standard,
  { color: c.label.control, display: 'inline-flex', alignItems: 'center', gap: '4px' }
])

/** Scope class for the pane's rows: every grouping picker's value reads label-control, a step
 *  brighter than the shared PickerControl's secondary (triple-class to outrank its `&&`). */
export const pickerTone = style({})
globalStyle(`${pickerTone} ${pickerValue}${pickerValue}${pickerValue}`, { color: c.label.control })

/** KNOB — the middle region's scroll ceiling. */
const MIDDLE_MAX_HEIGHT = '280px'

/** The scrollable order region between the dividers — wears the shared vertical eclipse fade
 *  (the bare `overflow-eclipse-y` class rides in the component, the Icon Picker precedent). */
export const middle = style({ position: 'relative', maxHeight: MIDDLE_MAX_HEIGHT, overflowY: 'auto' })

/** The list insertion line — the global drag primitives (--drag-line / --drop-line-thickness). */
export const dropLine = style({
  position: 'absolute',
  left: '8px',
  right: '8px',
  height: 'var(--drop-line-thickness, 2px)',
  borderRadius: 'var(--drop-line-thickness, 2px)',
  background: 'var(--drag-line)',
  pointerEvents: 'none'
})

/** A preview group heading (the muted footing tone) with its chips beneath. */
export const previewHeading = style([text.footnote.emphasized, { color: c.label.secondary, padding: '6px 8px 2px' }])
export const chipRow = style({ display: 'flex', alignItems: 'center', padding: '3px 8px' })
