// The FilterPane's rule grid + field variants. One grid owns the column geometry (D-9): connector ·
// what · operator · value · remove, uniform across rows via subgrid rows (a row must be a real
// element so its hover can reveal the ×). The operator column stays compact (fit-content of its
// widest label); What and Value split the spare room with What favored; everything truncates
// behind its own overflow before the pane grows past the max-width knob.
import { globalStyle, style } from '@vanilla-extract/css'
import { vars as colorVars } from '../../design-system/tokens/color.css'
import { duration, easing } from '../../design-system/tokens/motion'
import { TINT_STEPS, tintAt } from '../../design-system/tokens/tint'
import { text } from '../../design-system/tokens/typography.css'
import { field as fieldBase } from '../../design-system/components/interactionField.css'

const c = colorVars.color

/** KNOB — the pane's content-driven width ceiling. */
const FILTER_MAX_WIDTH = '420px'

/** KNOB — the pane's height floor (matches the hosts' leaf slider floor) so the "+" footer pins
 *  to the bottom edge like every other pane's footing. */
const FILTER_MIN_HEIGHT = '245px'

export const pane = style({
  maxWidth: FILTER_MAX_WIDTH,
  minHeight: FILTER_MIN_HEIGHT,
  display: 'flex',
  flexDirection: 'column'
})

/** The rule region grows to push the footer to the pane's bottom. */
export const body = style({ flex: '1 0 auto' })

export const grid = style({
  display: 'grid',
  gridTemplateColumns: 'minmax(40px, 1.4fr) fit-content(140px) minmax(36px, 1fr)',
  columnGap: '6px',
  rowGap: '4px',
  padding: '6px 0',
  alignItems: 'center',
  // The grid never drives the pane's width — it fills whatever the pane's other content set
  // (the flush divider is the gutter truth; fields span edge to edge and clip inside).
  width: 0,
  minWidth: '100%'
})

export const gridRow = style({
  gridColumn: '1 / -1',
  position: 'relative',
  display: 'grid',
  gridTemplateColumns: 'subgrid',
  alignItems: 'center'
})

/** The What cell — the row's lead: row 0's field sits FLUSH at the gutter; rows 2+ lead with
 *  their And/Or connector inside this cell, indenting the field. */
export const whatCell = style({
  display: 'flex',
  alignItems: 'center',
  gap: '6px',
  minWidth: 0
})

/** The one field stroke — the menu separator hairline as an inset ring. */
const fieldStroke = `inset 0 0 0 1px ${c.separator.line}`

/** The shared input-field recipe in its column: flush to the gutters, STANDARD field height
 *  (the interactionField 28px floor), body-size type, separator-hairline stroke. */
export const cellField = style([
  fieldBase,
  text.body.emphasized,
  {
    width: '100%',
    minWidth: 0,
    padding: '4px 8px',
    gap: '4px',
    border: 'none',
    cursor: 'default',
    color: c.label.control,
    overflow: 'hidden',
    whiteSpace: 'nowrap',
    boxShadow: fieldStroke
  }
])

globalStyle(`${cellField} > span`, {
  overflow: 'hidden',
  textOverflow: 'ellipsis',
  whiteSpace: 'nowrap'
})

/** The And/Or connector — a mini field in the footnote/secondary register (the trailing-option tone). */
export const connector = style([
  fieldBase,
  text.footnote.emphasized,
  {
    width: 'auto',
    minWidth: 0,
    minHeight: 0,
    padding: '2px 6px',
    gap: '2px',
    border: 'none',
    cursor: 'default',
    color: c.label.secondary,
    boxShadow: fieldStroke
  }
])

export const placeholder = style({ color: c.label.tertiary })

/** The hover-revealed row remove — floats over the row's right edge (absolute, off the grid flow)
 *  so the value field stays flush against the gutter; dead until its row is hovered. */
export const removeButton = style({
  position: 'absolute',
  right: '2px',
  top: '50%',
  transform: 'translateY(-50%)',
  border: 'none',
  background: 'none',
  padding: 0,
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
  color: c.label.tertiary,
  opacity: 0,
  cursor: 'default',
  selectors: { [`${gridRow}:hover &`]: { opacity: 1 } }
})

/** Matches = None — the rule region + footer dim and lock; the Matches row stays live. */
export const disabled = style({ opacity: 'var(--state-ghost)', pointerEvents: 'none' })

export const lockedCaption = style([text.footnote.standard, { color: c.label.secondary, padding: '8px 10px 4px' }])

/** The typed value input — the cell-field recipe as a bare <input>, focus lighting the shared
 *  inset accent stroke (the TextPicker recipe). */
export const cellInput = style([
  fieldBase,
  text.body.emphasized,
  {
    width: '100%',
    minWidth: 0,
    padding: '4px 8px',
    border: 'none',
    outline: 'none',
    fontFamily: 'inherit',
    color: c.label.control,
    boxShadow: fieldStroke,
    transition: `box-shadow ${duration.fast} ${easing.standard}`,
    selectors: {
      '&:focus, &:focus-visible': {
        outline: 'none',
        boxShadow: `inset 0 0 0 1px ${tintAt('var(--accent)', TINT_STEPS.secondary)}`
      }
    }
  }
])

/** The chip run inside a chips field — shrunk a step (the pane's subChip treatment rides in the
 *  component) and clipped to the cell. */
export const chipRun = style({
  display: 'inline-flex',
  alignItems: 'center',
  gap: '3px',
  minWidth: 0,
  overflow: 'hidden'
})

/** An icon-bearing picker option row — leading glyph + label, left-aligned. */
export const pickerOptionRow = style({
  display: 'flex',
  alignItems: 'center',
  gap: '6px',
  width: '100%',
  justifyContent: 'flex-start'
})
