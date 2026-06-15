import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, readFile, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { atomicWriteFile, writeJson, mutateJson, stableStringify } from './atomicWrite'

let dir: string
beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), 'pom-io-'))
})
afterEach(async () => {
  await rm(dir, { recursive: true, force: true })
})

describe('atomicWriteFile', () => {
  it('writes and overwrites a file', async () => {
    const p = join(dir, 'a.txt')
    await atomicWriteFile(p, 'first')
    expect(await readFile(p, 'utf8')).toBe('first')
    await atomicWriteFile(p, 'second')
    expect(await readFile(p, 'utf8')).toBe('second')
  })
})

describe('stableStringify', () => {
  it('is deterministic regardless of key insertion order', () => {
    expect(stableStringify({ b: 1, a: 2 })).toBe(stableStringify({ a: 2, b: 1 }))
  })

  it('sorts nested object keys but preserves array order', () => {
    expect(stableStringify({ z: { y: 1, x: 2 }, list: [3, 1, 2] })).toBe(
      '{\n  "list": [\n    3,\n    1,\n    2\n  ],\n  "z": {\n    "x": 2,\n    "y": 1\n  }\n}'
    )
  })
})

describe('writeJson', () => {
  it('writes sorted JSON with a trailing newline that parses back', async () => {
    const p = join(dir, 'c.json')
    const value = { b: 1, a: { d: 4, c: 3 } }
    await writeJson(p, value)
    const text = await readFile(p, 'utf8')
    expect(text.endsWith('\n')).toBe(true)
    expect(JSON.parse(text)).toEqual(value)
    expect(text).toBe(stableStringify(value) + '\n')
  })
})

describe('mutateJson', () => {
  it('read-modify-writes an existing file', async () => {
    const p = join(dir, 'state.json')
    await writeJson(p, { count: 1, keep: 'me' })
    const result = await mutateJson<{ count: number; keep?: string }>(
      p,
      () => ({ count: 0 }),
      (cur) => ({ ...cur, count: cur.count + 1 })
    )
    expect(result.count).toBe(2)
    expect(JSON.parse(await readFile(p, 'utf8'))).toEqual({ count: 2, keep: 'me' })
  })

  it('falls back when the file is missing', async () => {
    const p = join(dir, 'absent.json')
    const result = await mutateJson<{ items: string[] }>(
      p,
      () => ({ items: [] }),
      (cur) => ({ items: [...cur.items, 'x'] })
    )
    expect(result).toEqual({ items: ['x'] })
  })

  it('falls back when the file is unreadable JSON', async () => {
    const p = join(dir, 'corrupt.json')
    await writeFile(p, '{ not valid', 'utf8')
    const result = await mutateJson<{ n: number }>(
      p,
      () => ({ n: 9 }),
      (cur) => ({ n: cur.n + 1 })
    )
    expect(result).toEqual({ n: 10 })
  })
})
