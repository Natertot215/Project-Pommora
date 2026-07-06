import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtempSync, rmSync, writeFileSync, utimesSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { beginWalk, cachedParse, endWalk } from './walkCache'

// Backdate a file past the racy window so (mtime, size) is trusted immediately.
const cool = (path: string, secondsAgo = 10): void => {
  const t = (Date.now() - secondsAgo * 1000) / 1000
  utimesSync(path, t, t)
}

describe('walkCache', () => {
  let root: string
  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), 'walk-cache-'))
  })
  afterEach(() => rmSync(root, { recursive: true, force: true }))

  const walk = async <T>(path: string, parse: () => Promise<T>): Promise<T> => {
    beginWalk(root)
    const value = await cachedParse(path, parse)
    endWalk()
    return value
  }

  it('parses once while (mtime, size) hold, re-parses on change', async () => {
    const file = join(root, 'a.md')
    writeFileSync(file, 'one')
    cool(file)
    let parses = 0
    const parse = async (): Promise<string> => {
      parses++
      return `parsed-${parses}`
    }
    expect(await walk(file, parse)).toBe('parsed-1')
    expect(await walk(file, parse)).toBe('parsed-1') // cache hit — same value, no re-parse
    writeFileSync(file, 'two-longer')
    cool(file, 5)
    expect(await walk(file, parse)).toBe('parsed-2')
    expect(parses).toBe(2)
  })

  it('re-parses a hot file (mtime inside the racy window) every walk', async () => {
    const file = join(root, 'hot.md')
    writeFileSync(file, 'fresh')
    let parses = 0
    const parse = async (): Promise<number> => ++parses
    await walk(file, parse)
    await walk(file, parse)
    expect(parses).toBe(2)
  })

  it('prunes entries a walk does not touch, so a recreated file re-parses', async () => {
    const a = join(root, 'a.md')
    const b = join(root, 'b.md')
    writeFileSync(a, 'aaa')
    writeFileSync(b, 'bbb')
    cool(a)
    cool(b)
    let parses = 0
    const parse = async (): Promise<number> => ++parses
    beginWalk(root)
    await cachedParse(a, parse)
    await cachedParse(b, parse)
    endWalk()
    // A walk that only sees `a` prunes `b`'s entry.
    beginWalk(root)
    await cachedParse(a, parse)
    endWalk()
    beginWalk(root)
    await cachedParse(b, parse) // pruned — parses again despite unchanged (mtime, size)
    endWalk()
    expect(parses).toBe(3)
  })

  it('drops the cache when the walk root changes', async () => {
    const file = join(root, 'a.md')
    writeFileSync(file, 'aaa')
    cool(file)
    let parses = 0
    const parse = async (): Promise<number> => ++parses
    await walk(file, parse)
    beginWalk(join(root, 'elsewhere'))
    await cachedParse(file, parse)
    endWalk()
    expect(parses).toBe(2)
  })

  it('falls through uncached when the file cannot be statted', async () => {
    const missing = join(root, 'gone.md')
    let parses = 0
    const parse = async (): Promise<null> => {
      parses++
      return null
    }
    expect(await walk(missing, parse)).toBeNull()
    expect(await walk(missing, parse)).toBeNull()
    expect(parses).toBe(2) // never cached
  })
})
