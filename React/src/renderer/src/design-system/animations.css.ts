import { globalKeyframes, style } from '@vanilla-extract/css'

/**
 * Motion aliases. `dropdown-menu` is Pommora's standard pane/menu open — "Bloom": a zoom from the
 * trigger (scale → 1 + fade on the Bloom curve, no blur). Inspired by Apple's popover motion but
 * Pommora-native. Literal keyframe name so it reads as `animation: dropdown-menu …`. Consumers apply
 * the `dropdownMenu` class + set `--dropdown-origin` (defaults top center) so it blooms from its trigger.
 */
globalKeyframes('dropdown-menu', {
  from: { opacity: 0, transform: 'scale(0.5)' },
  to: { opacity: 1, transform: 'scale(1)' }
})

export const dropdownMenu = style({
  animation: 'dropdown-menu 380ms cubic-bezier(0.32, 0.72, 0, 1) both',
  transformOrigin: 'var(--dropdown-origin, top center)'
})
