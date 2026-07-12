import { describe, it, expect } from 'vitest'
import { scanConnections } from './scan'

const titles = (body: string) => scanConnections(body).map((c) => c.normalizedTitle).sort()

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
    expect(titles('see [[Notes [WIP] final]] and [[A [x] B]]')).toEqual(['a [x] b', 'notes [wip] final'])
    expect(titles('[[A]] then [[B]]')).toEqual(['a', 'b']) // adjacent links still split
  })
})
