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
