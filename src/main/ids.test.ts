import { describe, it, expect } from 'vitest'
import { newId, isUlid, adoptedId } from './ids'

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
