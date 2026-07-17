import { describe, it, expect } from 'vitest'
import { scanConnections } from './scan'

const titles = (body: string) =>
  scanConnections(body)
    .map((c) => c.normalizedTitle)
    .sort()

describe('scanConnections', () => {
  it('extracts page links and normalizes their titles', () => {
    expect(titles('See [[Alpha]] and [[Beta Page]].')).toEqual(['alpha', 'beta page'])
  })

  it('aggregates repeats (case/whitespace-insensitive) into multiplicity', () => {
    const out = scanConnections('[[Alpha]] then [[ alpha ]] and [[ALPHA]]')
    expect(out).toEqual([{ normalizedTitle: 'alpha', multiplicity: 3 }])
  })

  it('excludes image embeds and {{ }}, and drops a legacy pipe segment', () => {
    expect(titles('![[Cover.png]] {{macro}} [[Real|01H9XYZ]]')).toEqual(['real'])
  })

  it('ignores empty / whitespace-only links and returns [] for a plain body', () => {
    expect(scanConnections('[[]] [[   ]] no links here')).toEqual([])
  })

  it('tolerates internal brackets in a title (a `]` is content unless it closes the pair)', () => {
    expect(titles('see [[Notes [WIP] final]] and [[A [x] B]]')).toEqual([
      'a [x] b',
      'notes [wip] final',
    ])
    expect(titles('[[A]] then [[B]]')).toEqual(['a', 'b']) // adjacent links still split
  })

  it('caps title length and never backtracks on a pathological bracket run (ReDoS guard)', () => {
    // Under an unbounded `+` this would hang for seconds — completing at all IS the guard.
    expect(scanConnections('['.repeat(50000))).toEqual([])
    expect(scanConnections(`[[a|${'['.repeat(50000)}`)).toEqual([])
    // The title is capped at the filesystem name limit (255): at the bound matches, past it doesn't.
    expect(titles(`[[${'x'.repeat(255)}]]`)).toEqual(['x'.repeat(255)])
    expect(scanConnections(`[[${'x'.repeat(256)}]]`)).toEqual([])
  })
})
