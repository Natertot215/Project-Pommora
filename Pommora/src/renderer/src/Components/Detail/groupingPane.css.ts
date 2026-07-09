// The Grouping pane's row-tier knobs. Primary rows (Group By / Sub-Group / Date By) read the
// MenuItem default (Body, label-primary); a subordinate Order row reads a step quieter and
// tucks toward its parent so the pair reads grouped (C-8).
import { style } from '@vanilla-extract/css'
import { vars as colorVars } from '../../design-system/tokens/color.css'
import { text } from '../../design-system/tokens/typography.css'

const c = colorVars.color

/** KNOB — how far a subordinate Order row tucks toward its parent row. */
const SUB_ORDER_GAP = '-4px'

export const subRow = style({ marginTop: SUB_ORDER_GAP })

export const subLabel = style([text.control.emphasized, { color: c.label.secondary }])

/** The Group By row's trailing value — Control-size (the PickerControl trigger's weight class), a
 *  step LARGER than the menus' Footnote detail so the pane's lead value reads at full strength. */
export const groupByValue = style([
  text.control.standard,
  { color: c.label.secondary, display: 'inline-flex', alignItems: 'center', gap: '4px' }
])

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
