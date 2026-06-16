import { createGlobalTheme } from '@vanilla-extract/css'

// Color tokens mirrored from the Figma color collection: the solid spectrum,
// label tones, the window background, content surfaces, overlay fills,
// interaction states, the accent seed, and separators. Per-component soft tints
// (e.g. chips) and the accent's -fill / -text derive from these — see
// chip.css.ts and theme-vars.css.ts.
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
    // The app substrate — the base background (Figma "Background").
    background: {
      window: '#1A1A1B'
    },
    // Content surfaces layered on the window (Figma "Surface").
    surface: {
      primary: '#222225',
      secondary: '#252528',
      tertiary: '#333336'
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
    // Accent seed — the default accent (Figma "Accent/accent" → lavender). The
    // live accent is swappable at runtime via --accent; its -fill / -text DERIVE
    // from it (theme-vars.css.ts), so one property swap recolors everything.
    accent: {
      base: '#A78BCC'
    },
    // Hairlines (Figma "Separator").
    separator: {
      line: '#FFFFFF1F',
      border: '#FFFFFF29',
      segment: '#FFFFFF0F'
    }
  }
})
