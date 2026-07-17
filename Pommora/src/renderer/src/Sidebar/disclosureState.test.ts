import { describe, it, expect } from 'vitest'
import { loadOpen, saveOpen, DISCLOSURE_KEY } from './disclosureState'

function fakeStorage(seed: Record<string, string> = {}): Pick<Storage, 'getItem' | 'setItem'> {
  const store: Record<string, string> = { ...seed }
  return {
    getItem: (k) => (k in store ? store[k] : null),
    setItem: (k, v) => {
      store[k] = v
    },
  }
}

describe('sidebar disclosure state', () => {
  it('loadOpen falls back when unset, returns the stored value when set', () => {
    const s = fakeStorage()
    expect(loadOpen(s, 'v1', false)).toBe(false)
    expect(loadOpen(s, 'tier:areas', true)).toBe(true)
    saveOpen(s, 'v1', true)
    expect(loadOpen(s, 'v1', false)).toBe(true)
  })

  it('saveOpen merges into prior keys rather than clobbering', () => {
    const s = fakeStorage()
    saveOpen(s, 'v1', true)
    saveOpen(s, 'tier:topics', false)
    expect(loadOpen(s, 'v1', false)).toBe(true)
    expect(loadOpen(s, 'tier:topics', true)).toBe(false)
  })

  it('loadOpen tolerates missing or corrupt storage', () => {
    expect(loadOpen(fakeStorage(), 'v1', true)).toBe(true)
    expect(loadOpen(fakeStorage({ [DISCLOSURE_KEY]: 'not json' }), 'v1', true)).toBe(true)
  })
})
