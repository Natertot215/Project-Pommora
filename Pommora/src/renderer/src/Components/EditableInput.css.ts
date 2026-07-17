import { style } from '@vanilla-extract/css'

// Auto-sizing field: the input overlays a hidden mirror span in ONE grid cell, so the field
// shrink-wraps to its text through CSS reflow — never a per-keystroke layout read. Font + padding
// inherit from the caller's surface (the option chip), so the mirror measures in the same metrics.

export const autoSizeWrap = style({ display: 'inline-grid' })

export const autoSizeMirror = style({
  gridArea: '1 / 1',
  visibility: 'hidden',
  whiteSpace: 'pre',
  pointerEvents: 'none',
})

export const autoSizeInput = style({ gridArea: '1 / 1', width: '100%', minWidth: 0 })
