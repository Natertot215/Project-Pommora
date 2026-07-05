import { style } from '@vanilla-extract/css'
import { vars } from '../../tokens/color.css'
import { duration, easing } from '../../tokens/motion'
import { TINT_STEPS, tintAt } from '../../tokens/tint'
import { font } from '../../tokens/typography.css'
import { field } from '../interactionField.css'

const c = vars.color

/** The pane's own gutter — 4px between the input-field and the beaked edge, overriding PickerMenu's
 *  default 6px surface gutter (the top still clears the beak band via `--notch-h`). */
export const content = style({
  paddingTop: 'calc(var(--notch-h, 0px) + 4px) !important',
  paddingRight: '4px !important',
  paddingBottom: '4px !important',
  paddingLeft: '4px !important',
  alignItems: 'flex-start' // the field left-anchors in the pane so its caret sits at the left edge, never centred
})

/** The rename field — the shared input-field chrome at CalendarPicker's caret metrics (control size;
 *  the native caret scales with the font). `field-sizing` grows it to its text between a 100px floor
 *  and a 200px cap, then it scrolls internally. Focused, an `--accent` stroke at tint-secondary fades
 *  in over duration-fast; a consumer may scope `--accent` on the pane to tint it (a link wears its own
 *  colour), else it inherits the app accent. */
export const input = style([
  field,
  {
    // Undo `field`'s div-oriented layout so the bare input lays out its own single-line caret (the
    // CalendarPicker model): no flex, no 28px floor, and the caret sized to the control line — not body's
    // 16px on 12px text, which is what left the caret oversized + vertically off.
    display: 'block',
    minHeight: 0,
    lineHeight: font.scale.control.line,
    width: 'auto',
    minWidth: '100px',
    maxWidth: '200px',
    fieldSizing: 'content',
    textAlign: 'left', // caret hard-left in the field — explicit, not the inherited/UA default
    border: 'none',
    outline: 'none',
    fontFamily: 'inherit',
    fontSize: font.scale.control.size,
    fontWeight: font.weight.emphasized,
    color: c.label.primary,
    boxShadow: 'inset 0 0 0 1px transparent',
    transition: `box-shadow ${duration.fast} ${easing.standard}`,
    selectors: {
      '&:focus, &:focus-visible': {
        outline: 'none',
        boxShadow: `inset 0 0 0 1px ${tintAt('var(--accent)', TINT_STEPS.secondary)}`
      }
    }
  }
])
