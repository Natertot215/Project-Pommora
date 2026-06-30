import { describe, it, expect } from 'vitest'
import { chipColorFor } from './chipColorMap'

describe('chipColorFor', () => {
  it('maps the shared hues 1:1', () => {
    expect(chipColorFor('red')).toBe('red')
    expect(chipColorFor('blue')).toBe('blue')
    expect(chipColorFor('green')).toBe('green')
    expect(chipColorFor('purple')).toBe('purple')
    expect(chipColorFor('orange')).toBe('orange')
    expect(chipColorFor('yellow')).toBe('yellow')
    expect(chipColorFor('gray')).toBe('grey')
  })

  it('maps the non-1:1 colors to their nearest chip hue', () => {
    expect(chipColorFor('teal')).toBe('cyan')
    expect(chipColorFor('brown')).toBe('orange')
    expect(chipColorFor('pink')).toBe('lavender')
    expect(chipColorFor('indigo')).toBe('purple')
  })

  it('falls back to default for absent or unknown colors', () => {
    expect(chipColorFor(undefined)).toBe('default')
    expect(chipColorFor('chartreuse')).toBe('default')
  })

  // AreaColor carries an 'accent' value the chip palette has no equivalent for — pin that it lands
  // on the neutral default (an accent Area renders neutral in a table chip).
  it('maps the AreaColor "accent" to default', () => {
    expect(chipColorFor('accent')).toBe('default')
  })
})
