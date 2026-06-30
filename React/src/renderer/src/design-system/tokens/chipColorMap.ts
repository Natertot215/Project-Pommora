// Maps a property/context color (Notion's selectColor / AreaColor palette) onto a chip palette key
// (Part 2 G-3). Aligns at the boundary — the chip palette stays intact, the on-disk Notion colors map
// onto it. The 7 shared hues map 1:1; brown/pink/indigo have no chip equivalent and take a nearest
// color (tunable); teal→cyan; gray→grey. Absent/unknown → the neutral default.
//
// `import type` keeps this module runtime-pure (the vanilla-extract `chip.css` is never loaded here),
// so it stays unit-testable while the name list still single-sources from the chip palette.

import type { ChipColorName } from './chip.css'

const MAP: Record<string, ChipColorName> = {
  gray: 'grey',
  brown: 'orange',
  orange: 'orange',
  yellow: 'yellow',
  green: 'green',
  blue: 'blue',
  purple: 'purple',
  pink: 'lavender',
  red: 'red',
  teal: 'cyan',
  indigo: 'purple'
}

/** A Notion select / area color → its chip palette key; absent or unrecognized → the neutral default. */
export function chipColorFor(color: string | undefined): ChipColorName {
  return (color && MAP[color]) || 'default'
}
