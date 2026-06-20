import { describe, it, expect } from 'vitest'
import { expandShorthand, parseCalloutType, isCalloutLine } from './codec'

describe('callout codec (:: ⇄ > [!type])', () => {
  it(':: expands to the canonical note callout', () => {
    expect(expandShorthand('::')).toBe('> [!note] ')
  })
  it('::type expands to that type', () => {
    expect(expandShorthand('::warning')).toBe('> [!warning] ')
  })
  it('non-shorthand prefixes do not expand', () => {
    expect(expandShorthand('not a callout')).toBeNull()
    expect(expandShorthand(':')).toBeNull()
  })
  it('parses the type from the canonical form', () => {
    expect(parseCalloutType('> [!note] hello')).toBe('note')
    expect(parseCalloutType('> [!WARNING] hi')).toBe('warning')
    expect(parseCalloutType('> just a quote')).toBeNull()
  })
  it('round-trips: shorthand → canonical → detected type', () => {
    const canonical = expandShorthand('::info')!
    expect(isCalloutLine(canonical)).toBe(true)
    expect(parseCalloutType(canonical)).toBe('info')
  })
})
