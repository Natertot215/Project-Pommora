// The FilterPane's rule grid + field variants. One grid owns the column geometry (D-9): connector ·
// what · operator · value · remove, uniform across rows via subgrid rows (a row must be a real
// element so its hover can reveal the ×). The operator column stays compact (fit-content of its
// widest label); What and Value split the spare room with What favored; everything truncates
// behind its own overflow before the pane grows past the max-width knob.
import { globalStyle, style } from '@vanilla-extract/css'
import { vars as colorVars } from '../../design-system/tokens/color.css'
import { text } from '../../design-system/tokens/typography.css'
import { field as fieldBase } from '../../design-system/components/interactionField.css'

const c = colorVars.color

/** KNOB — the pane's content-driven width ceiling. */
const FILTER_MAX_WIDTH = '420px'

export const pane = style({ maxWidth: FILTER_MAX_WIDTH })

export const grid = style({
  display: 'grid',
  gridTemplateColumns: 'max-content minmax(72px, 1.4fr) fit-content(140px) minmax(64px, 1fr) 16px',
  columnGap: '6px',
  rowGap: '4px',
  padding: '6px 8px',
  alignItems: 'center'
})

export const gridRow = style({
  gridColumn: '1 / -1',
  display: 'grid',
  gridTemplateColumns: 'subgrid',
  alignItems: 'center'
})

/** The shared input-field recipe at grid-cell metrics: shrink-wrapped, control-sized, no 28px floor. */
export const cellField = style([
  fieldBase,
  text.control.emphasized,
  {
    width: 'auto',
    minWidth: 0,
    minHeight: 0,
    padding: '3px 8px',
    gap: '4px',
    border: 'none',
    cursor: 'default',
    color: c.label.control,
    overflow: 'hidden',
    whiteSpace: 'nowrap'
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
    color: c.label.secondary
  }
])

/** Row 0's empty connector cell — holds the column so rows 1+ read indented. */
export const connectorSpacer = style({ minWidth: '1px' })

export const placeholder = style({ color: c.label.tertiary })

/** The hover-revealed row remove — dead until its row is hovered. */
export const removeButton = style({
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

/** An icon-bearing picker option row — leading glyph + label, left-aligned. */
export const pickerOptionRow = style({
  display: 'flex',
  alignItems: 'center',
  gap: '6px',
  width: '100%',
  justifyContent: 'flex-start'
})
