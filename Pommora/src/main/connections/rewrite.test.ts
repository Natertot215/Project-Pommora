import { describe, it, expect } from 'vitest'
import { rewriteConnections } from './rewrite'

describe('rewriteConnections', () => {
  it('rewrites a normalized-matching link to the new title', () => {
    expect(rewriteConnections('go to [[Old Page]] now', 'Old Page', 'New Page')).toBe('go to [[New Page]] now')
  })

  it('matches case-insensitively and drops a legacy pipe', () => {
    expect(rewriteConnections('[[old page]] and [[Old Page|01H]]', 'Old Page', 'New')).toBe('[[New]] and [[New]]')
  })

  it('leaves non-matching links and image embeds untouched', () => {
    expect(rewriteConnections('[[Other]] and ![[Old.png]]', 'Old.png', 'X')).toBe('[[Other]] and ![[Old.png]]')
  })
})
