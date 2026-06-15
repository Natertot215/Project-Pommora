import { createGlobalTheme } from '@vanilla-extract/css'

// Solid spectrum — the chip/color hues from the Figma "Colors" collection.
// Solids only; fill / text / soft variants are added later. Values pulled from
// source, with the aliased cyan + lavender resolved.
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
    }
  }
})
