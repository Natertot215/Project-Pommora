import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { readAppConfig, writeAppConfig, appConfigPath, addRecent } from './appConfig'

let dir: string
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'pom-cfg-'))
})
afterEach(() => {
  rmSync(dir, { recursive: true, force: true })
})

describe('appConfig', () => {
  it('returns empty defaults when the file is absent', async () => {
    expect(await readAppConfig(dir)).toEqual({})
  })

  it('returns empty defaults when the file is malformed JSON', async () => {
    writeFileSync(appConfigPath(dir), 'not json {')
    expect(await readAppConfig(dir)).toEqual({})
  })

  it('returns empty defaults when the JSON root is not an object', async () => {
    writeFileSync(appConfigPath(dir), '[]')
    expect(await readAppConfig(dir)).toEqual({})
  })

  it('ignores a non-string lastNexusPath', async () => {
    writeFileSync(appConfigPath(dir), JSON.stringify({ lastNexusPath: 42 }))
    expect((await readAppConfig(dir)).lastNexusPath).toBeUndefined()
  })

  it('round-trips lastNexusPath through write then read', async () => {
    await writeAppConfig(dir, { lastNexusPath: '/Users/x/Nexus' })
    expect((await readAppConfig(dir)).lastNexusPath).toBe('/Users/x/Nexus')
  })

  it('round-trips recents through write then read', async () => {
    await writeAppConfig(dir, { recents: ['/a', '/b'] })
    expect((await readAppConfig(dir)).recents).toEqual(['/a', '/b'])
  })

  it('filters non-string entries out of recents', async () => {
    writeFileSync(appConfigPath(dir), JSON.stringify({ recents: ['/a', 42, null, '/b'] }))
    expect((await readAppConfig(dir)).recents).toEqual(['/a', '/b'])
  })

  it('round-trips a valid trashMode through write then read', async () => {
    await writeAppConfig(dir, { trashMode: 'system' })
    expect((await readAppConfig(dir)).trashMode).toBe('system')
    await writeAppConfig(dir, { trashMode: 'nexus' })
    expect((await readAppConfig(dir)).trashMode).toBe('nexus')
  })

  it('ignores an invalid trashMode (consumer defaults to nexus)', async () => {
    writeFileSync(appConfigPath(dir), JSON.stringify({ trashMode: 'recycle-bin' }))
    expect((await readAppConfig(dir)).trashMode).toBeUndefined()
  })
})

describe('addRecent', () => {
  it('prepends a new path, newest first', () => {
    expect(addRecent(['a', 'b'], 'c')).toEqual(['c', 'a', 'b'])
  })

  it('moves an existing path to the front (dedupe, no duplicates)', () => {
    expect(addRecent(['a', 'b', 'c'], 'b')).toEqual(['b', 'a', 'c'])
  })

  it('caps the list at the given size', () => {
    expect(addRecent(['a', 'b', 'c'], 'd', 3)).toEqual(['d', 'a', 'b'])
  })

  it('defaults the cap to 10 (drops the oldest at 11)', () => {
    const ten = Array.from({ length: 10 }, (_, i) => `p${i}`)
    const result = addRecent(ten, 'new')
    expect(result).toHaveLength(10)
    expect(result[0]).toBe('new')
    expect(result).not.toContain('p9') // the oldest fell off
  })

  it('is idempotent for the same path (no duplicates, stays at front)', () => {
    expect(addRecent(['a'], 'a')).toEqual(['a'])
  })
})
