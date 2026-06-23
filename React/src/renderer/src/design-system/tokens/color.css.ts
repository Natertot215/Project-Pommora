import { createGlobalTheme } from '@vanilla-extract/css'
import { WINDOW_BG } from '@shared/theme'

// Primitives — the base system palette. Grey/white/black are the single source for
// every derived tone: labels are system-white at an opacity, and fills / states /
// separators are system-grey at an opacity. The spectrum solids and the opaque
// surfaces are their own values (not derived from a primitive).
const primitive = createGlobalTheme(':root', {
  color: {
    system: {
      grey: '#71717A',
      white: '#F1F1F1',
      black: '#010101'
    }
  }
})

// base @ alpha — apply an opacity to a primitive. color-mix(… X%, transparent) is
// the project's established opacity mechanism (see tint.ts / theme-vars.css.ts),
// so a derived token references the primitive var rather than baking its hex.
const greyA = (pct: string): string => `color-mix(in srgb, ${primitive.color.system.grey} ${pct}, transparent)`
const whiteA = (pct: string): string => `color-mix(in srgb, ${primitive.color.system.white} ${pct}, transparent)`

// Derived tokens mirrored from the Figma color collection.
const derived = createGlobalTheme(':root', {
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
    // Label tones — system-white at full / 65% / 35% (separate from the type ramp).
    label: {
      primary: primitive.color.system.white,
      secondary: whiteA('65%'),
      tertiary: whiteA('35%')
    },
    // The app substrate — the base background (Figma "Background"). Single source:
    // @shared/theme WINDOW_BG, so the Electron window + this token never drift.
    background: {
      window: WINDOW_BG
    },
    // Content surfaces layered on the window (Figma "Surface").
    surface: {
      primary: '#202022',
      secondary: '#2A2A2E',
      tertiary: '#3A3A3E'
    },
    // Overlay fills over a surface — system-grey ramp at 20 / 15 / 10 / 6 / 4%.
    fill: {
      primary: greyA('20%'),
      secondary: greyA('15%'),
      tertiary: greyA('10%'),
      quaternary: greyA('6%'),
      quinary: greyA('4%')
    },
    // Interaction states (Figma "States") — system-grey at hover 2.5% / selected 5%.
    state: {
      hover: greyA('2.5%'),
      selected: greyA('5%')
    },
    // Hairlines (Figma "Separator") — system-grey at line/border 25% / segment 20%.
    separator: {
      line: greyA('25%'),
      border: greyA('25%'),
      segment: greyA('20%')
    }
  }
})

// One token object: primitives under `color.system`, everything else alongside.
export const vars = {
  color: {
    ...derived.color,
    system: primitive.color.system
  }
}
