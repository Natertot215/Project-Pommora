// One duration + easing vocabulary — every transition shares a feel instead of scattering ad-hoc values.

export const duration = {
  fast: '180ms', // quick hover / affordance feedback (grips, button hovers)
  disclosure: '180ms', // disclosure + chevron open/close (sidebar + editor) — tunable apart from `fast`
  dropdown: '225ms', // inline picker + autocomplete open/close — the Bloom keyframes, snappier + symmetric
  base: '280ms', // sidebar + inspector slide + the reflow that tracks them
  slow: '350ms'
} as const

export const easing = {
  // The disclosure chevron's curve — the shared everyday ease. Swap this one value
  // to shift the whole system's feel (e.g. to a stronger ease-out); both the chevron
  // and the reveal follow because they reference the same token.
  standard: 'ease',
  out: 'cubic-bezier(0.22, 1, 0.36, 1)' // ease-out (quint), no bounce
} as const

export type Duration = keyof typeof duration
export type Easing = keyof typeof easing
