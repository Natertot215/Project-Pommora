import { style, styleVariants } from '@vanilla-extract/css'
import { vars as colorVars } from './color.css'
import { text, truncateHoverScroll } from './typography.css'
import { TINT_STEPS, tint, tintAt } from './tint'

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
 *  the × itself is `chipRemove`; the label's TEXT tail blurs beneath it (`chipLabelText` +
 *  `chipLabelBlur`). */
export const chipRemovable = style({ position: 'relative' })

// The cap lives on the LABEL, not the chip (a % width is unreliable in a shrink-to-fit flex chip): the
// label truncates at `--chip-max` and the chip wraps it snugly, so the ellipsis lands at the padding
// edge instead of floating mid-chip. `--chip-max` (80px default) is overridable per context. The
// ellipsis-at-rest / scroll-on-hover behaviour is the shared `truncateHoverScroll`; the cap is the add.
// `position: relative` anchors the removable chip's blurred twin; masks NEVER go on this box — a
// mask here erases every descendant, the twin included.
export const chipLabel = style([truncateHoverScroll, { maxWidth: 'var(--chip-max, 80px)', position: 'relative' }])

// Hovering a REMOVABLE chip BLURS the label's tail under the × — a true blur, not a fade-out
// (Nathan: a mask alone "is a cutoff, not blur"), touching only the TEXT (a backdrop strip washes
// the fill — rejected live). Two perfectly-stacked copies of the same text crossfade over one ramp
// ending at the ×'s left edge (10px inside the text run's end): the crisp copy masks OUT across it
// while its blurred twin masks IN, so the letters visibly smear into the clear zone the × floats in.
const crispRamp =
  'linear-gradient(to right, transparent 0, #000000 var(--scroll-fade, 0px), #000000 calc(100% - 18px), transparent calc(100% - 8px))'
const blurRamp = 'linear-gradient(to right, transparent calc(100% - 18px), #000000 calc(100% - 8px))'

/** The label's real text — masked out across the ramp only while the chip is hovered. */
export const chipLabelText = style({
  selectors: {
    [`${chipRemovable}:hover &`]: { maskImage: crispRamp, WebkitMaskImage: crispRamp }
  }
})

/** The blurred twin — same string and font, overlaid at the text origin so the metrics line up
 *  glyph-for-glyph, but painted in the FILL color (`--chip-fill`) so the tail melts into the
 *  pill instead of hazing in the text color; visible only where the crisp copy eclipses. */
export const chipLabelBlur = style({
  position: 'absolute',
  top: 0,
  left: 0,
  whiteSpace: 'nowrap',
  color: 'var(--chip-fill)',
  filter: 'blur(2px)',
  maskImage: blurRamp,
  WebkitMaskImage: blurRamp,
  opacity: 0,
  pointerEvents: 'none',
  transition: 'opacity var(--duration-fast) var(--ease-standard)',
  selectors: {
    [`${chipRemovable}:hover &`]: { opacity: 1 }
  }
})

/** tint() + the chip's FILL color as a var so descendants can paint in it — the blurred twin
 *  melts the label's tail INTO the fill, not into a text-colored haze. A surface that overrides
 *  the fill (ContextChip's neutral quaternary) must override `--chip-fill` alongside it. */
const chipTint = (base: string): ReturnType<typeof tint> & { vars: Record<string, string> } => ({
  ...tint(base),
  vars: { '--chip-fill': tintAt(base, TINT_STEPS.primary) }
})

export const chipColor = styleVariants({
  red: chipTint(solid.red),
  blue: chipTint(solid.blue),
  green: chipTint(solid.green),
  purple: chipTint(solid.purple),
  lavender: chipTint(solid.lavender),
  cyan: chipTint(solid.cyan),
  lightBlue: chipTint(solid.lightBlue),
  orange: chipTint(solid.orange),
  yellow: chipTint(solid.yellow),
  grey: chipTint(solid.grey),
  default: chipTint(solid.greyDefault)
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
 * shifts the chip's width; the label's tail blurs beneath it (`chipLabelText`/`chipLabelBlur`).
 * Hidden = inert (`pointerEvents: none`) so a rest-state chip click still reaches the cell.
 * The width anchors the ramp: the blur's clear zone starts at this edge.
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
