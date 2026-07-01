// The color-exchange layer — maps an external color name (Notion's selectColor / the Swift AreaColor
// palette) onto one of the app's render palettes. `chipColorFor` is the chip-palette accessor (Part 2
// G-3); other exchanges add a sibling accessor here rather than re-deriving the mapping. Aligns at the
// boundary — the app palette stays intact, the on-disk names map onto it. The 7 shared hues map 1:1;
// brown/pink/indigo have no chip equivalent and take a nearest color (tunable); teal→cyan; gray→grey.
// Absent/unknown → the neutral default.
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
