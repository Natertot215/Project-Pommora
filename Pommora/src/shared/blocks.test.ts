import { describe, expect, it } from 'vitest'
import { blockPatchProblem, coerceBlockHost, knownBlock, rawLayoutSchema } from './blocks'

describe('knownBlock', () => {
  it('types the three known entry kinds', () => {
    expect(knownBlock({ id: 'a', type: 'markdown' })).toEqual({ id: 'a', type: 'markdown' })
    expect(knownBlock({ id: 'b', type: 'page', page_id: 'p1' })).toMatchObject({ type: 'page', page_id: 'p1' })
    expect(knownBlock({ id: 'c', type: 'view', view_id: 'view_x' })).toMatchObject({ type: 'view' })
  })

  it('keeps foreign keys on a known entry (loose)', () => {
    expect(knownBlock({ id: 'a', type: 'markdown', future_field: 1 })).toMatchObject({ future_field: 1 })
  })

  it('returns null for unknown types and garbage — the caller renders inert', () => {
    expect(knownBlock({ id: 'x', type: 'widget' })).toBeNull()
    expect(knownBlock({ type: 'page', page_id: 'p1' })).toBeNull()
    expect(knownBlock('nope')).toBeNull()
    expect(knownBlock(null)).toBeNull()
  })
})

describe('rawLayoutSchema', () => {
  it('accepts a wire-shaped tree and rejects garbage', () => {
    const tree = {
      bands: [
        {
          node: {
            kind: 'row',
            ratios: [0.5, 0.5],
            children: [
              { kind: 'tile', id: 'a', h: 100 },
              { kind: 'column', children: [{ kind: 'tile', id: 'b', h: 40 }] }
            ]
          }
        }
      ]
    }
    expect(rawLayoutSchema.safeParse(tree).success).toBe(true)
    expect(rawLayoutSchema.safeParse({ bands: 'no' }).success).toBe(false)
  })
})

describe('blockPatchProblem', () => {
  it('passes well-shaped patches and names the malformed ones', () => {
    expect(blockPatchProblem({ layout: { bands: [] } })).toBeNull()
    expect(blockPatchProblem({ blocks: [], locked: true })).toBeNull()
    expect(blockPatchProblem({ layout: 'garbage' })).toBe('Malformed layout.')
    expect(blockPatchProblem({ blocks: 'no' as unknown as unknown[] })).toBe('blocks must be an array.')
    expect(blockPatchProblem({ locked: 'yes' as unknown as boolean })).toBe('locked must be a boolean.')
  })
})

describe('coerceBlockHost', () => {
  it('accepts the homepage host and rejects the rest', () => {
    expect(coerceBlockHost({ kind: 'homepage' })).toEqual({ kind: 'homepage' })
    expect(coerceBlockHost({ kind: 'area', path: 'x' })).toBeNull()
    expect(coerceBlockHost('homepage')).toBeNull()
  })
})
