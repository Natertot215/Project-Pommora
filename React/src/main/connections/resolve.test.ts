import { describe, it, expect } from 'vitest'
import { buildLinkIndex, resolveTitle } from './resolve'

describe('buildLinkIndex', () => {
  it('keys pages by normalized title and collects same-title ids', () => {
    const idx = buildLinkIndex([
      { id: 'a', title: 'Alpha' },
      { id: 'b', title: 'beta' },
      { id: 'a2', title: ' ALPHA ' },
      { id: 'blank', title: '   ' }
    ])
    expect(idx.get('alpha')).toEqual(['a', 'a2'])
    expect(idx.get('beta')).toEqual(['b'])
    expect(idx.has('')).toBe(false) // blank title skipped
  })
})

describe('resolveTitle', () => {
  const idx = buildLinkIndex([
    { id: 'a', title: 'Alpha' },
    { id: 'dup1', title: 'Dup' },
    { id: 'dup2', title: 'dup' }
  ])

  it('resolves a unique title, flags ambiguity, and reports phantoms', () => {
    expect(resolveTitle('alpha', idx)).toEqual({ status: 'resolved', targetId: 'a' })
    expect(resolveTitle('dup', idx)).toEqual({ status: 'ambiguous' })
    expect(resolveTitle('missing', idx)).toEqual({ status: 'phantom' })
  })
})
