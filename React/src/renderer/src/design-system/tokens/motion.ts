// Motion — the app's one duration + easing vocabulary, so every transition (the
// disclosure reveal + its chevron, menus, dropdowns, drag) shares a feel instead of
// scattering ad-hoc values. Exposed as CSS vars via theme-vars.css.ts (for plain
// CSS); vanilla-extract / inline-style consumers import these directly.

export const duration = {
  fast: '180ms', // disclosure open/close + its chevron — in sync
  base: '250ms', // macOS standard UI-animation duration (NSAnimationContext default) — sidebar slide + reflow
  slow: '320ms'
} as const

export const easing = {
  // The disclosure chevron's curve — the shared everyday ease. Swap this one value
  // to shift the whole system's feel (e.g. to a stronger ease-out); both the chevron
  // and the reveal follow because they reference the same token.
  standard: 'ease',
  out: 'cubic-bezier(0.22, 1, 0.36, 1)' // ease-out (quint), no bounce — larger moves (sidebar slide, reveals)
} as const

export type Duration = keyof typeof duration
export type Easing = keyof typeof easing
