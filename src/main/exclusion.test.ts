import { describe, it, expect } from 'vitest'
import { shouldSkipDir } from './exclusion'

describe('shouldSkipDir', () => {
  it('skips convention dirs', () => {
    expect(shouldSkipDir('.git', '.git', [])).toBe(true)
    expect(shouldSkipDir('.nexus', '.nexus', [])).toBe(true)
    expect(shouldSkipDir('_internal', '_internal', [])).toBe(true)
    expect(shouldSkipDir('node_modules', 'node_modules', [])).toBe(true)
  })

  it('keeps normal dirs', () => {
    expect(shouldSkipDir('Vault A', 'Vault A', [])).toBe(false)
  })

  it('applies user excludes by segment-prefix, NFC + case-insensitive', () => {
    expect(shouldSkipDir('Archive', 'Archive', ['archive'])).toBe(true)
    expect(shouldSkipDir('Sub', 'Vault A/Sub', ['Vault A'])).toBe(true)
    expect(shouldSkipDir('Other', 'Other', ['Vault A'])).toBe(false)
    expect(shouldSkipDir('Vault A', 'Vault A', ['Vault A/Sub'])).toBe(false) // prefix is deeper, not a match
  })
})
