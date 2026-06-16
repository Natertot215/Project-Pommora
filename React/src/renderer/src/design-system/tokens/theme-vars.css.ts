import { globalStyle } from '@vanilla-extract/css'
import { vars as colorVars } from './color.css'
import { font } from './typography.css'

// Bridge: expose the (hashed) vanilla-extract tokens as stable-named CSS custom
// properties, so plain CSS (the showcase chrome) can reference them via var(--…)
// instead of hardcoding the values — one source of truth across .ts and .css.
globalStyle(':root', {
  vars: {
    '--label-primary': colorVars.color.label.primary,
    '--bg-window': colorVars.color.background.window,
    '--separator-border': colorVars.color.separator.border,
    '--font-family': font.family
  }
})
