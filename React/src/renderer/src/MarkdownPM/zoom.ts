// Editor zoom — ONE slider value drives the editor body font size, ready to wire to a per-page
// zoom later. The slider runs 0–2 with a default of 1.0 (= the 15pt base). The mapping is
// EXPONENTIAL — `2^(z−1)` — so each ±1 on the slider halves/doubles the size and the endpoints
// land exactly where asked: 0 → 2× smaller (0.5×), 1 → base (1×), 2 → 2× larger (2×).
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
