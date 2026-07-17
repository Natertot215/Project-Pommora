import { describe, it, expect } from 'vitest'
import { rewriteConnections } from './rewrite'
import { scanConnections } from './scan'

describe('rewriteConnections', () => {
  it('rewrites a normalized-matching link to the new title', () => {
    expect(rewriteConnections('go to [[Old Page]] now', 'Old Page', 'New Page')).toBe(
      'go to [[New Page]] now',
    )
  })

  it('matches case-insensitively and drops a legacy pipe', () => {
    expect(rewriteConnections('[[old page]] and [[Old Page|01H]]', 'Old Page', 'New')).toBe(
      '[[New]] and [[New]]',
    )
  })

  it('leaves non-matching links and image embeds untouched', () => {
    expect(rewriteConnections('[[Other]] and ![[Old.png]]', 'Old.png', 'X')).toBe(
      '[[Other]] and ![[Old.png]]',
    )
  })

  it('rewrites TO a title with internal brackets and it round-trips', () => {
    // The healed link parses back to the same normalized title (no corruption of the surrounding text).
    const body = rewriteConnections('go to [[Old]] now', 'Old', 'New [v2] final')
    expect(body).toBe('go to [[New [v2] final]] now')
    expect(scanConnections(body).map((c) => c.normalizedTitle)).toEqual(['new [v2] final'])
  })

  it('rewrites FROM a title that itself contains brackets', () => {
    expect(rewriteConnections('[[Notes [WIP] final]] here', 'Notes [WIP] final', 'Done')).toBe(
      '[[Done]] here',
    )
  })
})
