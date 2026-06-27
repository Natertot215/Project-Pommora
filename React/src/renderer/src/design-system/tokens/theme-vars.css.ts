import { globalStyle } from '@vanilla-extract/css'
import { DEFAULT_ACCENT } from '@shared/types'
import { vars as colorVars } from './color.css'
import { font } from './typography.css'
import { size } from './size.css'
import { TINT_STEPS } from './tint'
import { duration, easing } from './motion'

// Bridge: expose the (hashed) vanilla-extract tokens as stable-named CSS custom
// properties, so plain CSS (the showcase chrome) can reference them via var(--…)
// instead of hardcoding the values — one source of truth across .ts and .css.
globalStyle(':root', {
  vars: {
    // Primitives — the base palette every grey/white tone derives from.
    '--system-grey': colorVars.color.system.grey,
    '--system-white': colorVars.color.system.white,
    '--system-black': colorVars.color.system.black,
    // Tint scale — opacity steps applied to a base color (color-mix). Step values only.
    '--tint-primary': `${TINT_STEPS.primary}%`,
    '--tint-secondary': `${TINT_STEPS.secondary}%`,
    '--tint-tertiary': `${TINT_STEPS.tertiary}%`,
    '--tint-quaternary': `${TINT_STEPS.quaternary}%`,
    '--tint-solid': `${TINT_STEPS.solid}%`,
    '--label-primary': colorVars.color.label.primary,
    '--label-secondary': colorVars.color.label.secondary,
    '--label-tertiary': colorVars.color.label.tertiary,
    '--bg-window': colorVars.color.background.window,
    '--surface-primary': colorVars.color.surface.primary,
    '--surface-secondary': colorVars.color.surface.secondary,
    '--surface-tertiary': colorVars.color.surface.tertiary,
    // Overlay fills (system-grey ramp) — used for cards/chips over a surface.
    '--fill-primary': colorVars.color.fill.primary,
    '--fill-secondary': colorVars.color.fill.secondary,
    '--fill-tertiary': colorVars.color.fill.tertiary,
    '--fill-quaternary': colorVars.color.fill.quaternary,
    '--fill-quinary': colorVars.color.fill.quinary,
    '--separator-border': colorVars.color.separator.border,
    // Interaction states (Figma "States") — system-grey at hover 2.5% / selected 5%.
    '--state-hover': colorVars.color.state.hover,
    '--state-selected': colorVars.color.state.selected,
    // Accent: a pointer, never a baked color. The static seed is the default
    // spectrum solid (DEFAULT_ACCENT); applyAccent overrides --accent at runtime
    // from settings — any spectrum color, or the OS accent. -fill is a 15% tint
    // of whatever --accent currently is; tinted accent text IS --accent itself.
    '--accent': colorVars.color.solid[DEFAULT_ACCENT],
    '--accent-fill': 'color-mix(in srgb, var(--accent) 15%, transparent)',
    '--accent-text': 'var(--accent)',
    // The OS/system accent, always reflected (applySystemAccent overrides it at
    // runtime from the OS, independent of the Pommora --accent setting). Seeded
    // with the default solid so SSR/cold paint has a value.
    '--system-accent': colorVars.color.solid[DEFAULT_ACCENT],
    // Semantic link colors (labels side, not tints): external links wear the OS
    // accent, internal connections wear the Pommora accent; code is systemRed @ 0.85.
    '--link': 'var(--system-accent)',
    '--connection': 'var(--accent)',
    '--code': `color-mix(in srgb, ${colorVars.color.solid.red} 85%, transparent)`,
    '--font-family': font.family,
    // Weight ladder — so plain CSS single-sources the same numbers as the text styles.
    '--weight-standard': font.weight.standard,
    '--weight-emphasized': font.weight.emphasized,
    '--weight-semibold': font.weight.semibold,
    '--weight-bold': font.weight.bold,
    // Type sizes plain CSS needs (single-sourced from the scale); add more as consumers appear.
    '--text-title3-size': font.scale.title3.size,
    // Icon-size ladder — so plain-CSS glyphs (e.g. the fold chevron) route to the same steps.
    '--icon-xs': size.icon.xs,
    '--icon-sm': size.icon.sm,
    '--icon-md': size.icon.md,
    '--icon-lg': size.icon.lg,
    '--icon-xl': size.icon.xl,
    // Motion — shared durations + easing so every transition reads as one system.
    '--duration-fast': duration.fast,
    '--duration-base': duration.base,
    '--duration-slow': duration.slow,
    '--ease-standard': easing.standard,
    '--ease-out': easing.out
  }
})
