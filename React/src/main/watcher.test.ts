import { describe, it, expect } from 'vitest'
import { ignoredUnder } from './watcher'

// The watcher's only non-trivial pure logic: which paths it skips. Checks segments
// BELOW the root, so a dot-segment in the root's own absolute path can't blank it.
describe('ignoredUnder', () => {
  const ignored = ignoredUnder('/nexus')

  it('keeps the root itself and normal entities (incl. _underscore sidecars)', () => {
    expect(ignored('/nexus')).toBe(false)
    expect(ignored('/nexus/Notes/Page.md')).toBe(false)
    expect(ignored('/nexus/Areas/Work/_area.json')).toBe(false)
  })

  it('ignores .nexus, .trash, and dotfiles anywhere below the root', () => {
    expect(ignored('/nexus/.nexus/index.db')).toBe(true)
    expect(ignored('/nexus/.trash/old.md')).toBe(true)
    expect(ignored('/nexus/.DS_Store')).toBe(true)
    expect(ignored('/nexus/Notes/.hidden/x.md')).toBe(true)
  })

  it('does not ignore paths outside the root', () => {
    expect(ignored('/elsewhere/file.md')).toBe(false)
  })

  it('works when the root path itself contains a dot-segment', () => {
    const underDot = ignoredUnder('/Users/me/.config/nexus')
    expect(underDot('/Users/me/.config/nexus/Notes/Page.md')).toBe(false)
    expect(underDot('/Users/me/.config/nexus/.trash/x.md')).toBe(true)
  })
})
