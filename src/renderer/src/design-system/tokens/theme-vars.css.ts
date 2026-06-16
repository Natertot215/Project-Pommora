import { globalStyle } from '@vanilla-extract/css'
import { vars as colorVars } from './color.css'
import { font } from './typography.css'

// Bridge: expose the (hashed) vanilla-extract tokens as stable-named CSS custom
// properties, so plain CSS (the showcase chrome) can reference them via var(--…)
// instead of hardcoding the values — one source of truth across .ts and .css.
globalStyle(':root', {
  vars: {
    '--label-primary': colorVars.color.label.primary,
    '--label-secondary': colorVars.color.label.secondary,
    '--label-tertiary': colorVars.color.label.tertiary,
    '--bg-window': colorVars.color.background.window,
    '--surface-primary': colorVars.color.surface.primary,
    '--surface-secondary': colorVars.color.surface.secondary,
    '--surface-tertiary': colorVars.color.surface.tertiary,
    '--separator-border': colorVars.color.separator.border,
    // Accent: the seed defaults to lavender but is swappable at runtime
    // (applyAccent sets --accent on :root from the nexus config). -fill / -text
    // are color-mix derivations, so swapping --accent alone recolors everything.
    '--accent': colorVars.color.accent.base,
    '--accent-fill': 'color-mix(in srgb, var(--accent) 15%, transparent)',
    '--accent-text': 'color-mix(in srgb, var(--accent) 70%, white)',
    '--font-family': font.family
  }
})
