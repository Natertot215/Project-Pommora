import { style, styleVariants } from '@vanilla-extract/css'
import { vars as colorVars } from './color.css'
import { text, truncateHoverScroll } from './typography.css'
import { TINT_STEPS, tint, tintAt } from './tint'

const solid = colorVars.color.solid

// ═══════════════════════════════════════════════════════════════════════════
// § SHAPE PRIMITIVES — one class per chip shape, each complete on its own.
// Compose exactly ONE shape with ONE color: `${chipPill} ${chipColor.blue}`.
// Adding a new type = one block: compose `chipBase`, state the shape's
// geometry, export it. Text ramp comes from the base — never restate it.
// ═══════════════════════════════════════════════════════════════════════════

const chipBase = style([
  text.control.semibold,
  {
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: '4px',
    boxSizing: 'border-box',
    borderStyle: 'solid',
    whiteSpace: 'nowrap'
  }
])

/** chip-pill — the standard text chip (status/select/multi/context labels). */
export const chipPill = style([
  chipBase,
  {
    height: '20px',
    padding: '0 6px',
    borderRadius: '10px',
    borderWidth: '2px'
  }
])

/** chip-capsule — the icon-only shape (a single small glyph, no label; the showcase's
 *  "Select" row). Pill geometry with the glyph centered. */
export const chipCapsule = style([
  chipBase,
  {
    height: '20px',
    padding: '0 6px',
    borderRadius: '10px',
    borderWidth: '2px',
    gap: 0
  }
])

/** The box shape's bare frame — geometry only, no chip base. Exported for non-chip
 *  consumers that style themselves (the editor's task checkbox rides it under md-checkbox). */
export const chipBoxGeometry = style({
  width: '17px',
  height: '17px',
  padding: 0,
  borderRadius: '5.5px',
  borderWidth: '1.5px'
})

/** chip-box — the fixed 17×17 rounded square (radius 5.5, 1.5px stroke); holds one
 *  glyph (the checkbox look's checkmark). */
export const chipBox = style([chipBase, chipBoxGeometry])

// ═══════════════════════════════════════════════════════════════════════════
// § REMOVE-× MELT MACHINERY — the hover-revealed × + the label-tail melt.
// LOAD-BEARING (Guidelines/Build-Gotchas.md § Chip Melt): masks STATIC from
// mount, reveals flip OPACITIES only, the removable label is pointer-inert.
// Any change here runs the re-verify matrix — computed styles lie for this
// bug class; only live hovers are truth.
// ═══════════════════════════════════════════════════════════════════════════

/** A chip that carries a hover-revealed remove ×. The modifier only anchors the affordance;
 *  the × itself is `chipRemove`; the label's TEXT tail blurs beneath it (`chipLabelText` +
 *  `chipLabelBlur`). */
export const chipRemovable = style({ position: 'relative' })

// The cap lives on the LABEL, not the chip (a % width is unreliable in a shrink-to-fit flex chip): the
// label truncates at `--chip-max` and the chip wraps it snugly, so the ellipsis lands at the padding
// edge instead of floating mid-chip. `--chip-max` (80px default) is overridable per context. The
// ellipsis-at-rest / scroll-on-hover behaviour is the shared `truncateHoverScroll`; the cap is the add.
// `position: relative` anchors the removable chip's twins; masks NEVER go on this box — a
// mask here erases every descendant, the twins included. On a REMOVABLE chip the label is
// pointer-inert (inherited by the text): hovering the label body must do nothing, and if the
// label or text ever LEAVES :hover in the frame that flips the ×-reveal, Chromium drops the
// reveal's repaint beneath it — so they must never enter the hover chain at all.
export const chipLabel = style([
  truncateHoverScroll,
  {
    maxWidth: 'var(--chip-max, 80px)',
    position: 'relative',
    selectors: {
      [`${chipRemovable} &`]: { pointerEvents: 'none' }
    }
  }
])

// Hovering a REMOVABLE chip BLURS the label's tail under the × — a true blur, not a fade-out
// (Nathan: a mask alone "is a cutoff, not blur"), touching only the TEXT (a backdrop strip washes
// the fill — rejected live). Two perfectly-stacked copies of the same text crossfade over one ramp
// ending at the ×'s left edge (10px inside the text run's end): the crisp copy masks OUT across it
// while its blurred twin masks IN, so the letters visibly smear into the clear zone the × floats in.
const crispRamp =
  'linear-gradient(to right, transparent 0, #000000 var(--scroll-fade, 0px), #000000 calc(100% - 18px), transparent calc(100% - 8px))'
const blurRamp = 'linear-gradient(to right, transparent calc(100% - 18px), #000000 calc(100% - 8px))'

/**
 * The remove × — its box doubles as the reveal's hover zone (the chip's right third), so it is
 * always hittable; only hovering IT reveals it and melts the label tail beneath. Defined before
 * the label styles because their reveal selectors reference it.
 */
export const chipRemove = style({
  position: 'absolute',
  top: 0,
  right: 0,
  height: '100%',
  width: '33%',
  minWidth: '16px',
  zIndex: 1,
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'flex-end',
  padding: '0 2.5px 0 0',
  border: 'none',
  background: 'none',
  color: 'inherit',
  cursor: 'pointer',
  opacity: 0,
  transition: 'opacity var(--duration-fast) var(--ease-standard)',
  selectors: {
    '&:hover': { opacity: 1 }
  }
})

// The reveal is keyed on the ×'s own :hover through a SIBLING combinator (the × precedes the
// label in the DOM), and it may only ever flip OPACITIES. Chromium drops the repaint of any
// mask-image change on this inline text (none→gradient AND stop-swap alike) unless the restyle
// rides an ancestor :hover — `:has()`, sibling selectors, class toggles, and inline styles all
// compute the mask without painting it. Static masks + opacity flips paint everywhere.
const reveal = `${chipRemove}:hover ~ ${chipLabel} &`

/** The label's real text — swapped out for the pre-masked twins the instant the × zone is
 *  hovered (no transition: the melt twin is pixel-identical where its mask is opaque, so a
 *  crossfade would only dim the stack mid-flight). `position: relative` is load-bearing: it
 *  gives the span its own paint layer, without which the sibling-keyed opacity flip computes
 *  but never repaints (the same dropped invalidation the reveal note above describes). */
export const chipLabelText = style({
  position: 'relative',
  selectors: {
    [reveal]: { opacity: 0 }
  }
})

/** The crisp melt twin — the same string overlaid at the text origin with the ramp STATICALLY
 *  applied, revealed by opacity alone (see the reveal note above). Clamped to the label box so
 *  a truncated label melts at its clip edge instead of ending in a bare cut. */
export const chipLabelMelt = style({
  position: 'absolute',
  top: 0,
  left: 0,
  maxWidth: '100%',
  overflow: 'hidden',
  whiteSpace: 'nowrap',
  maskImage: crispRamp,
  WebkitMaskImage: crispRamp,
  opacity: 0,
  pointerEvents: 'none',
  selectors: {
    [reveal]: { opacity: 1 }
  }
})

/** The blurred twin — same string and font, overlaid at the text origin so the metrics line up
 *  glyph-for-glyph, but painted in the FILL color (`--chip-fill`) so the tail melts into the
 *  pill instead of hazing in the text color; visible only where the crisp copy eclipses.
 *  Deliberately NOT transitioned: a fade on a masked element can strand its final un-hover
 *  frame (the dropped-repaint family above), leaving a smear on the resting pill. */
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
  selectors: {
    [reveal]: { opacity: 1 }
  }
})

// ═══════════════════════════════════════════════════════════════════════════
// § COLOR — the unified tint, one variant per palette key. Shape-agnostic:
// every shape above composes with any `chipColor.*`.
// ═══════════════════════════════════════════════════════════════════════════

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
