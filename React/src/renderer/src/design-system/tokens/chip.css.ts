import { style, styleVariants } from '@vanilla-extract/css'
import { vars as colorVars } from './color.css'
import { text, truncateHoverScroll } from './typography.css'
import { tint } from './tint'

const solid = colorVars.color.solid

// One source for the Control/Emphasized text ramp — never re-state size/line/weight here.
// Color via `chipColor.*`; shape variant via `chipCheckbox`. Compose: `${chip} ${chipColor.blue}`.
export const chip = style([
  text.control.semibold,
  {
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: '4px',
    boxSizing: 'border-box',
    height: '20px',
    padding: '0 6px',
    borderRadius: '10px',
    borderStyle: 'solid',
    borderWidth: '2px',
    whiteSpace: 'nowrap'
  }
])

// The cap lives on the LABEL, not the chip (a % width is unreliable in a shrink-to-fit flex chip): the
// label truncates at `--chip-max` and the chip wraps it snugly, so the ellipsis lands at the padding
// edge instead of floating mid-chip. `--chip-max` (80px default) is overridable per context. The
// ellipsis-at-rest / scroll-on-hover behaviour is the shared `truncateHoverScroll`; the cap is the add.
export const chipLabel = style([truncateHoverScroll, { maxWidth: 'var(--chip-max, 80px)' }])

export const chipColor = styleVariants({
  red: tint(solid.red),
  blue: tint(solid.blue),
  green: tint(solid.green),
  purple: tint(solid.purple),
  lavender: tint(solid.lavender),
  cyan: tint(solid.cyan),
  lightBlue: tint(solid.lightBlue),
  orange: tint(solid.orange),
  yellow: tint(solid.yellow),
  grey: tint(solid.grey),
  default: tint(solid.greyDefault)
})

/** The chip palette keys — the single source consumers (cells, `colorMap`) target. */
export type ChipColorName = keyof typeof chipColor

/**
 * Checkbox chip — a fixed 17×17 rounded square (radius 5.5) with a 1.5px stroke;
 * holds only a checkmark. Pill = a text `chip`; Select = a `chip` with an icon
 * (both are pills — no shape modifier needed).
 */
export const chipCheckbox = style({
  width: '17px',
  height: '17px',
  padding: 0,
  borderRadius: '5.5px',
  borderWidth: '1.5px'
})
