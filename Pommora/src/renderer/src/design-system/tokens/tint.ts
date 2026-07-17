// The tint system — kept in a PLAIN module (not a *.css.ts) so it can export
// functions: vanilla-extract serializes every export of a *.css.ts into a virtual
// CSS module and a function throws. chip.css.ts builds chipColor.* from `tint`; the
// showcase reads the scale + `tint('var(--accent)')`.
import { vars as colorVars } from './color.css'

const labelPrimary = colorVars.color.label.primary

/**
 * The tint scale — opacity steps applied to a base color (the Figma "Tint" model:
 * a tint is an opacity, not a baked color). One source for every tinted surface —
 * chips, tinted segments, tinted buttons — where a component picks a step and the
 * base color is supplied at the call site.
 *   primary 60 · secondary 40 · tertiary 20 · quaternary 15 · solid 100
 */
export const TINT_STEPS = {
  primary: 60,
  secondary: 40,
  tertiary: 20,
  quaternary: 15,
  solid: 100,
} as const

export type TintStep = keyof typeof TINT_STEPS

/** A base color at a tint step — `base` at `step%` over transparent (or the opaque
 *  base at 100%). */
export const tintAt = (base: string, step: number): string =>
  step >= 100 ? base : `color-mix(in srgb, ${base} ${step}%, transparent)`

/**
 * Chip recipe — fill = tint-primary (60%), stroke = tint-secondary (40%), and
 * label-with-tint text: `label-primary` washed with a tint-quaternary (15%) amount
 * of the base, so chip text reads as the label color rather than the assigned color.
 * Compose `${chip} ${chipColor.blue}`.
 */
export const tint = (base: string): { background: string; borderColor: string; color: string } => ({
  background: tintAt(base, TINT_STEPS.primary),
  borderColor: tintAt(base, TINT_STEPS.secondary),
  color: `color-mix(in srgb, ${base} ${TINT_STEPS.quaternary}%, ${labelPrimary})`,
})
