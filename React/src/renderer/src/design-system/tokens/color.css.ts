import { createGlobalTheme } from '@vanilla-extract/css'

// Color tokens mirrored from the Figma color collection: the solid spectrum,
// label tones, the window background, content surfaces, overlay fills,
// interaction states, and separators. Per-component soft tints (e.g. chips) and
// the runtime accent (a pointer to one of these solids) derive from these —
// see chip.css.ts and theme-vars.css.ts.
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
      secondary: '#F1F1F1A6',
      tertiary: '#F1F1F159'
    },
    // The app substrate — the base background (Figma "Background").
    background: {
      window: '#1A1A1B'
    },
    // Content surfaces layered on the window (Figma "Surface").
    surface: {
      primary: '#1E1E20',
      secondary: '#222224',
      tertiary: '#2C2C2F'
    },
    // Overlay fills over a surface — base #71717A at five alphas (Figma "Fills").
    fill: {
      primary: '#71717A39',
      secondary: '#71717A26',
      tertiary: '#71717A1A',
      quaternary: '#71717A0F',
      quinary: '#71717A0A'
    },
    // Interaction states (Figma "States") — fills base #71717A at hover 2.5% / selected 5%.
    state: {
      hover: '#71717A06',
      selected: '#71717A0D'
    },
    // Hairlines (Figma "Separator") — fills base #71717A at line/border 25% / segment 20%.
    separator: {
      line: '#71717A40',
      border: '#71717A40',
      segment: '#71717A33'
    }
  }
})
