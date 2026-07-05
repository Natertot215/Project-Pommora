import { describe, it, expect } from 'vitest'
import { normalizeTitle } from './connections'

describe('normalizeTitle', () => {
  it('trims surrounding whitespace/newlines and case-folds', () => {
    expect(normalizeTitle('  My Page \n')).toBe('my page')
    expect(normalizeTitle('PROJECT')).toBe('project')
  })

  it('collapses titles that differ only by case/whitespace to one key', () => {
    expect(normalizeTitle(' Notes')).toBe(normalizeTitle('notes '))
  })
})
