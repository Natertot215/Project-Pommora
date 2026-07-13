// The per-block Scale model (G-10): a fixed set of discrete zoom factors a tile can carry. The factor
// is user-facing and RELATIVE to the tile's natural size (1.0 = no change). It rides ONE CSS var
// --block-zoom (keyed off `cls`); the font + glyphs + handle all derive from it. No JS font math — the
// factor is applied linearly in CSS, so it never touches the editor's clamped zoom curve.

export const DEFAULT_ZOOM = 1
export const ZOOM_FACTORS: readonly number[] = [1.25, 1, 0.85, 0.65, 0.5]

export interface ZoomStep {
  factor: number
  /** The `.spm-tile` class that sets --block-zoom; empty for 1.0 (the var falls back to 1). */
  cls: string
  /** Compact form for the menu row's trailing value ("0.5x"). */
  inline: string
  /** Two-decimal form for the picker list ("0.50x"). */
  label: string
}

const step = (factor: number): ZoomStep => ({
  factor,
  cls: factor === DEFAULT_ZOOM ? '' : `blk-zoom-${String(Math.round(factor * 100)).padStart(3, '0')}`,
  inline: `${factor}x`,
  label: `${factor.toFixed(2)}x`
})

export const ZOOM_STEPS: ZoomStep[] = ZOOM_FACTORS.map(step)

/** Resolve a stored factor to its step. Absent → 1.0; any other value SNAPS to the nearest ratified
 *  step, so an off-grid factor (a hand-edit or foreign import) still renders + reads as its closest
 *  step and is clearable through the picker — never silently stuck at a scale the picker can't show. */
export function zoomStep(factor?: number): ZoomStep {
  const target = factor ?? DEFAULT_ZOOM
  return ZOOM_STEPS.reduce((best, s) => (Math.abs(s.factor - target) < Math.abs(best.factor - target) ? s : best))
}
