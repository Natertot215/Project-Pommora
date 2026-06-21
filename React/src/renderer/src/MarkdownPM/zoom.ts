// Editor zoom — one slider value (0–2, default 1.0 = 15pt base) drives the body font size. The
// mapping is EXPONENTIAL (`2^(z−1)`) so each ±1 halves/doubles the size.
export const EDITOR_BASE_PT = 15
export const ZOOM_DEFAULT = 1
export const ZOOM_MIN = 0
export const ZOOM_MAX = 2

export function clampZoom(z: number): number {
  return Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, z))
}

/** Slider value → font-size multiplier. 0 → 0.5×, 1 → 1×, 2 → 2×. */
export function zoomMultiplier(z: number): number {
  return Math.pow(2, clampZoom(z) - 1)
}

/** Effective editor body font size (px) for a slider value. */
export function zoomFontSize(z: number): number {
  return EDITOR_BASE_PT * zoomMultiplier(z)
}
