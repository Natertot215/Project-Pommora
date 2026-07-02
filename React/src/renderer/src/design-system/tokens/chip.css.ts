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

/** A chip that carries a hover-revealed remove ×. The modifier only anchors the affordance;
 *  the × itself is `chipRemove` with its `chipFrost` strip dissolving the label tail beneath it. */
export const chipRemovable = style({ position: 'relative' })

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
 * holds only a checkmark. Pill = a text `chip` — no shape modifier needed.
 */
export const chipCheckbox = style({
  width: '17px',
  height: '17px',
  padding: 0,
  borderRadius: '5.5px',
  borderWidth: '1.5px'
})

/**
 * Capsule chip — the icon-only shape (a single small glyph, no label; the showcase's
 * "Select" row). Geometry is the pill's with the icon centered; the named class exists
 * so consumers target the shape instead of re-deriving `chip` + icon content ad hoc.
 */
export const chipCapsule = style({
  padding: '0 6px',
  gap: 0
})

/**
 * The remove × — hover-revealed at the chip's right edge, painted in the chip's TEXT color
 * (`color: inherit` — the label recipe rides down). Overlaid (absolute) so revealing it never
 * shifts the chip's width; the `chipFrost` strip inside it backdrop-blurs the label tail so the
 * text dissolves beneath the crisp glyph. Hidden = inert (`pointerEvents: none`) so a rest-state
 * chip click still reaches the cell.
 */
export const chipRemove = style({
  position: 'absolute',
  top: 0,
  right: 0,
  height: '100%',
  width: '16px',
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
  padding: 0,
  border: 'none',
  background: 'none',
  color: 'inherit',
  cursor: 'pointer',
  opacity: 0,
  pointerEvents: 'none',
  transition: 'opacity var(--duration-fast) var(--ease-standard)',
  selectors: {
    [`${chipRemovable}:hover &`]: { opacity: 1, pointerEvents: 'auto' }
  }
})

/**
 * The frost — a backdrop-blur strip under the ×, ramping in from the left (masking an element
 * masks its backdrop effect) so the label tail dissolves instead of hard-clipping; the rest of
 * the label stays crisp. A DIRECT chip child, never inside the × button: an opacity-transitioned
 * ancestor becomes the strip's backdrop root and the filter samples nothing (verified live —
 * the blur silently no-ops). It anchors inside the chip's padding box, so the border stays sharp
 * by construction; the right-side radius keeps the strip inside the pill's rounded cap.
 */
export const chipFrost = style({
  position: 'absolute',
  top: 0,
  bottom: 0,
  right: 0,
  width: '26px',
  backdropFilter: 'blur(8px)',
  WebkitBackdropFilter: 'blur(8px)',
  borderRadius: '0 8px 8px 0',
  maskImage: 'linear-gradient(to right, transparent 0, #000000 12px)',
  WebkitMaskImage: 'linear-gradient(to right, transparent 0, #000000 12px)',
  opacity: 0,
  pointerEvents: 'none',
  transition: 'opacity var(--duration-fast) var(--ease-standard)',
  selectors: {
    [`${chipRemovable}:hover &`]: { opacity: 1 }
  }
})
