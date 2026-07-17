import { globalKeyframes, style } from '@vanilla-extract/css'
import { duration } from './tokens/motion'

// The Bloom curve — Pommora-native, Apple-inspired. The one special-cased named curve (not a token).
const BLOOM = 'cubic-bezier(0.32, 0.72, 0, 1)'

// Navigation/Settings menus use the slower `slow`-token Bloom here; PickerMenu + AutocompletePanel use
// `dropdownOpen`/`dropdownClose` below (same keyframes, snappier `dropdown` token).
globalKeyframes('dropdown-menu', {
  from: { opacity: 0, transform: 'scale(0.5)' },
  to: { opacity: 1, transform: 'scale(1)' },
})

export const dropdownMenu = style({
  animation: `dropdown-menu ${duration.slow} ${BLOOM} both`,
  transformOrigin: 'var(--dropdown-origin, top center)',
})

// Retract — pane shrinks back toward its trigger so a dismiss withdraws rather than cuts.
globalKeyframes('dropdown-menu-out', {
  from: { opacity: 1, transform: 'scale(1)' },
  to: { opacity: 0, transform: 'scale(0.92)' },
})

export const dropdownMenuClosing = style({
  animation: `dropdown-menu-out ${duration.slow} ${BLOOM} both`,
  transformOrigin: 'var(--dropdown-origin, top center)',
})

// Same Bloom keyframes + curve as `dropdownMenu`, on the snappier symmetric `dropdown` token.
// PickerMenu + AutocompletePanel use these; Navigation/Settings menus keep the slower Bloom above.
export const dropdownOpen = style({
  animation: `dropdown-menu ${duration.dropdown} ${BLOOM} both`,
  transformOrigin: 'var(--dropdown-origin, top center)',
})

export const dropdownClose = style({
  animation: `dropdown-menu-out ${duration.dropdown} ${BLOOM} both`,
  transformOrigin: 'var(--dropdown-origin, top center)',
})

// Title reveal — the ViewDropdown's labeled title sliding in/out as Show/Hide Title toggles. The panes'
// Bloom curve on the snappy `dropdown` token, expressed as a transition timing (a two-state morph, not
// a keyframe) so a consumer drops it onto whatever properties slide.
export const titleReveal = `${duration.dropdown} ${BLOOM}`
