import { createGlobalTheme } from '@vanilla-extract/css'

// Color tokens from the Figma "Colors" collection: the solid spectrum + label
// tones. Per-component soft tints (e.g. chips) are derived from the solids —
// see chip.css.ts. Aliased cyan + lavender resolved to their solids.
export const vars = createGlobalTheme(':root', {
  color: {
    solid: {
      red: '#FF453A',
      orange: '#FF9F0A',
      yellow: '#FFD60A',
      green: '#32D74B',
      lightBlue: '#7EC8E3',
      cyan: '#41959F',
      blue: '#0A84FF',
      purple: '#BF5AF2',
      lavender: '#A78BCC',
      grey: '#8E8E93',
      greyDefault: '#48484A'
    },
    // Label tones on #F1F1F1 — text colors, separate from the type ramp.
    label: {
      primary: '#F1F1F1',
      secondary: 'rgba(241, 241, 241, 0.65)',
      tertiary: 'rgba(241, 241, 241, 0.35)'
    }
  }
})
