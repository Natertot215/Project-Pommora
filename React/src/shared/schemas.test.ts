import { describe, it, expect } from 'vitest'
import {
  pageTypeSidecar,
  pageCollectionSidecar,
  pageSetSidecar,
  areaSidecar,
  topicSidecar
} from './schemas'

describe('folder sidecar schemas', () => {
  it('parses a minimal page type (only id required)', () => {
    expect(pageTypeSidecar.parse({ id: 'T1' })).toEqual({ id: 'T1' })
  })

  it('retains foreign keys (looseObject) — the key enhancement over Swift', () => {
    const parsed = pageTypeSidecar.parse({ id: 'T1', plugin_field: 'keep', nested: { a: 1 } })
    expect(parsed).toMatchObject({ id: 'T1', plugin_field: 'keep', nested: { a: 1 } })
  })

  it('rejects a sidecar with no id (id is load-bearing)', () => {
    expect(pageTypeSidecar.safeParse({ icon: 'star' }).success).toBe(false)
  })

  it('keeps order arrays and optional fields', () => {
    const v = { id: 'C1', type_id: 'T1', page_order: ['p2', 'p1'], set_order: ['s1'] }
    expect(pageCollectionSidecar.parse(v)).toMatchObject(v)
  })

  it('page set carries collection_id + page_order', () => {
    const v = { id: 'S1', collection_id: 'C1', page_order: ['p1'] }
    expect(pageSetSidecar.parse(v)).toMatchObject(v)
  })
})

describe('context sidecar schemas', () => {
  it('requires tier; area adds optional color', () => {
    expect(areaSidecar.parse({ id: 'A1', tier: 1, color: 'blue' })).toMatchObject({
      id: 'A1',
      tier: 1,
      color: 'blue'
    })
    expect(topicSidecar.parse({ id: 'TP1', tier: 2 })).toMatchObject({ id: 'TP1', tier: 2 })
  })

  it('rejects a context with no tier', () => {
    expect(topicSidecar.safeParse({ id: 'X' }).success).toBe(false)
  })

  it('preserves the reserved blocks[] as a foreign key (not modeled)', () => {
    const parsed = areaSidecar.parse({ id: 'A1', tier: 1, blocks: [] })
    expect(parsed).toMatchObject({ id: 'A1', tier: 1, blocks: [] })
  })
})
