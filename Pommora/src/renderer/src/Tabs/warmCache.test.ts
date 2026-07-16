import { beforeEach, describe, expect, it } from 'vitest'
import { captureWarm, clearWarm, dropWarmTab, readWarm } from './warmCache'

beforeEach(() => clearWarm()) // module state — never leaks across tests

describe('warmCache', () => {
  it('round-trips a capture and merges partial writes under one key', () => {
    captureWarm('t1', 'page:a', { scrollTop: 120 })
    captureWarm('t1', 'page:a', { editorState: { doc: 'x' } })
    expect(readWarm('t1', 'page:a')).toEqual({ scrollTop: 120, editorState: { doc: 'x' } })
  })

  it('isolates tabs — the same entity warms independently per tab', () => {
    captureWarm('t1', 'page:a', { scrollTop: 1 })
    captureWarm('t2', 'page:a', { scrollTop: 2 })
    expect(readWarm('t1', 'page:a')?.scrollTop).toBe(1)
    expect(readWarm('t2', 'page:a')?.scrollTop).toBe(2)
  })

  it('evicts the stalest entry past the per-tab cap (I-7), sparing recently-captured ones', () => {
    for (let i = 0; i < 21; i++) captureWarm('t1', `page:p${i}`, { scrollTop: i })
    expect(readWarm('t1', 'page:p0')).toBeUndefined() // the 21st capture rolled the oldest off
    expect(readWarm('t1', 'page:p20')?.scrollTop).toBe(20)
    // Re-capturing an old key refreshes its slot, so the NEXT eviction takes the now-stalest instead.
    captureWarm('t1', 'page:p1', { scrollTop: 99 })
    captureWarm('t1', 'page:p21', { scrollTop: 21 })
    expect(readWarm('t1', 'page:p1')?.scrollTop).toBe(99)
    expect(readWarm('t1', 'page:p2')).toBeUndefined()
  })

  it('dropWarmTab clears one tab; clearWarm clears everything', () => {
    captureWarm('t1', 'page:a', { scrollTop: 1 })
    captureWarm('t2', 'page:b', { scrollTop: 2 })
    dropWarmTab('t1')
    expect(readWarm('t1', 'page:a')).toBeUndefined()
    expect(readWarm('t2', 'page:b')?.scrollTop).toBe(2)
    clearWarm()
    expect(readWarm('t2', 'page:b')).toBeUndefined()
  })
})
