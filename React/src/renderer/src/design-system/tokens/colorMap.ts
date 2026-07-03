// The color-exchange layer — maps an external color name (a legacy Notion select color / the Swift
// AreaColor palette) onto one of the app's render palettes. `chipColorFor` is the chip-palette accessor (Part 2
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

// The render-palette keys (ChipColorName minus 'default'), inlined so this module stays runtime-pure
// (chip.css is never loaded here). An option's stored color IS a solid key now, so a key already in
// the palette is its own render key — pass it through before consulting the legacy Notion map, which
// only covers old on-disk names (and never reached lightBlue/cyan/grey/lavender).
const PALETTE: ReadonlySet<string> = new Set([
  'red',
  'orange',
  'yellow',
  'green',
  'lightBlue',
  'cyan',
  'blue',
  'purple',
  'lavender',
  'grey'
])

/** A stored option / area color → its chip palette key. A solid key passes straight through; a legacy
 *  Notion name maps; absent or unrecognized → the neutral default. */
export function chipColorFor(color: string | undefined): ChipColorName {
  if (color && PALETTE.has(color)) return color as ChipColorName
  return (color && MAP[color]) || 'default'
}
