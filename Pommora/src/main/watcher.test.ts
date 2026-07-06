import { describe, it, expect } from 'vitest'
import { ignoredUnder } from './watcher'

// The watcher's only non-trivial pure logic: which paths it skips. Checks segments
// BELOW the root, so a dot-segment in the root's own absolute path can't blank it.
describe('ignoredUnder', () => {
  const ignored = ignoredUnder('/nexus')

  it('watches normal entities, _underscore sidecars, AND .nexus contexts/settings', () => {
    expect(ignored('/nexus')).toBe(false)
    expect(ignored('/nexus/Notes/Page.md')).toBe(false)
    expect(ignored('/nexus/Areas/Work/_area.json')).toBe(false)
    // .nexus holds user-meaningful config — Contexts + settings must auto-refresh externally.
    expect(ignored('/nexus/.nexus/areas/Work/_area.json')).toBe(false)
    expect(ignored('/nexus/.nexus/settings.json')).toBe(false)
    expect(ignored('/nexus/.nexus/state.json')).toBe(false)
  })

  it('ignores the churning index, the trash, and dotfile cruft', () => {
    expect(ignored('/nexus/.nexus/index.db')).toBe(true)
    expect(ignored('/nexus/.nexus/index.db-wal')).toBe(true)
    expect(ignored('/nexus/.nexus/index.db-shm')).toBe(true)
    expect(ignored('/nexus/.trash/old.md')).toBe(true)
    expect(ignored('/nexus/.DS_Store')).toBe(true)
    expect(ignored('/nexus/Notes/.hidden/x.md')).toBe(true)
  })

  it('does not ignore paths outside the root', () => {
    expect(ignored('/elsewhere/file.md')).toBe(false)
  })

  it('ignores user-excluded folders (case/NFC-insensitive, prefix match, whole segments only)', () => {
    const withExcluded = ignoredUnder('/nexus', ['Agenda', 'Deep/Nested'])
    expect(withExcluded('/nexus/Agenda/Task.md')).toBe(true)
    expect(withExcluded('/nexus/agenda/sub/Task.md')).toBe(true)
    expect(withExcluded('/nexus/Deep/Nested/x.md')).toBe(true)
    expect(withExcluded('/nexus/Deep/Other/x.md')).toBe(false)
    expect(withExcluded('/nexus/Agenda.md')).toBe(false) // a file merely NAMED like the folder
    expect(withExcluded('/nexus/Notes/Agenda/x.md')).toBe(false) // exclusions anchor at the root
  })

  it('works when the root path itself contains a dot-segment', () => {
    const underDot = ignoredUnder('/Users/me/.config/nexus')
    expect(underDot('/Users/me/.config/nexus/Notes/Page.md')).toBe(false)
    expect(underDot('/Users/me/.config/nexus/.nexus/settings.json')).toBe(false)
    expect(underDot('/Users/me/.config/nexus/.trash/x.md')).toBe(true)
  })
})
