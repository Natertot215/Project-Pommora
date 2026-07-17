import { describe, it, expect } from 'vitest'
import { matchesCommand } from './Commands'

const key = (k: string, mods: Partial<KeyboardEvent> = {}): KeyboardEvent =>
  ({
    key: k,
    metaKey: false,
    ctrlKey: false,
    altKey: false,
    shiftKey: false,
    ...mods,
  }) as KeyboardEvent

describe('matchesCommand', () => {
  it('matches cmd+e exactly', () => {
    expect(matchesCommand('cmd+e', key('e', { metaKey: true }))).toBe(true)
    expect(matchesCommand('cmd+e', key('E', { metaKey: true }))).toBe(true)
  })
  it('rejects a wrong or extra modifier (no double-fire across overlapping bindings)', () => {
    expect(matchesCommand('cmd+e', key('e', { ctrlKey: true }))).toBe(false)
    expect(matchesCommand('cmd+e', key('e', { metaKey: true, shiftKey: true }))).toBe(false)
    expect(matchesCommand('cmd+e', key('e'))).toBe(false)
  })
  it('matches multi-modifier specs case-insensitively', () => {
    expect(matchesCommand('Cmd+Shift+K', key('k', { metaKey: true, shiftKey: true }))).toBe(true)
  })
  it('an absent or empty spec never matches', () => {
    expect(matchesCommand(undefined, key('e', { metaKey: true }))).toBe(false)
    expect(matchesCommand('', key('e', { metaKey: true }))).toBe(false)
  })
})
