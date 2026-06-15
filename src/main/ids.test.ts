import { describe, it, expect } from 'vitest'
import { newId, isUlid, adoptedId, mintPropertyId } from './ids'

describe('newId / isUlid', () => {
  it('mints valid, unique ULIDs', () => {
    const a = newId()
    const b = newId()
    expect(isUlid(a)).toBe(true)
    expect(isUlid(b)).toBe(true)
    expect(a).not.toBe(b)
  })

  it('is monotonic — a batch sorts in mint order', () => {
    const ids = Array.from({ length: 50 }, () => newId())
    expect([...ids].sort()).toEqual(ids)
  })

  it('rejects non-ULIDs', () => {
    expect(isUlid('')).toBe(false)
    expect(isUlid('not-a-ulid')).toBe(false)
    expect(isUlid(adoptedId('x'))).toBe(false)
  })
})

describe('adoptedId', () => {
  it('is stable for the same path', () => {
    expect(adoptedId('Notes/Page.md')).toBe(adoptedId('Notes/Page.md'))
  })

  it('differs for different paths', () => {
    expect(adoptedId('Notes/A.md')).not.toBe(adoptedId('Notes/B.md'))
  })

  it('is the adopted-<16 hex> shape', () => {
    expect(adoptedId('x')).toMatch(/^adopted-[0-9a-f]{16}$/)
  })
})

describe('mintPropertyId', () => {
  it('mints a prop_<ulid> id whose suffix is a valid ULID', () => {
    const id = mintPropertyId()
    expect(id.startsWith('prop_')).toBe(true)
    expect(isUlid(id.slice('prop_'.length))).toBe(true)
  })

  it('mints unique ids', () => {
    expect(mintPropertyId()).not.toBe(mintPropertyId())
  })
})
