import { createGlobalTheme } from '@vanilla-extract/css'

// Color tokens mirrored from the Figma color collection: the solid spectrum,
// label tones, backgrounds, overlay fills, interaction states, accent, and
// separators. Per-component soft tints (e.g. chips) derive from the solids —
// see chip.css.ts.
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
    },
    // Window + surface backgrounds (Figma "Background").
    background: {
      primary: '#222225',
      secondary: '#252528',
      tertiary: '#333336',
      window: '#1A1A1B'
    },
    // Overlay fills over a surface — base #71717A at five alphas (Figma "Fills").
    fill: {
      primary: '#71717A39',
      secondary: '#71717A26',
      tertiary: '#71717A1A',
      quaternary: '#71717A0F',
      quinary: '#71717A0A'
    },
    // Interaction states (Figma "States").
    state: {
      hover: '#8E8E9305',
      selected: '#8E8E9314'
    },
    // Accent = lavender (Figma "Accent").
    accent: {
      base: '#A78BCC',
      fill: '#A78BCC26',
      text: '#C0AEDD'
    },
    // Hairlines (Figma "Separator").
    separator: {
      line: '#FFFFFF1F',
      border: '#FFFFFF29',
      segment: '#FFFFFF0F'
    }
  }
})
