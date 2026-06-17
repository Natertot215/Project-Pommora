import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { sessionRoot, openSession, closeSession, resolveRestorePath } from './session'

describe('session — open/close', () => {
  beforeEach(() => closeSession())

  it('starts empty', () => {
    expect(sessionRoot()).toBeNull()
  })

  it('opens then closes', () => {
    openSession('/Users/x/Nexus')
    expect(sessionRoot()).toBe('/Users/x/Nexus')
    closeSession()
    expect(sessionRoot()).toBeNull()
  })
})

describe('resolveRestorePath', () => {
  let dir: string
  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), 'pom-sess-'))
  })
  afterEach(() => {
    rmSync(dir, { recursive: true, force: true })
  })

  it('restores a readable directory', async () => {
    expect(await resolveRestorePath({ lastNexusPath: dir })).toBe(dir)
  })

  it('returns null when no path is persisted', async () => {
    expect(await resolveRestorePath({})).toBeNull()
  })

  it('returns null when the path no longer exists', async () => {
    expect(await resolveRestorePath({ lastNexusPath: join(dir, 'gone') })).toBeNull()
  })

  it('returns null when the path is a file, not a directory', async () => {
    const file = join(dir, 'a-file.md')
    writeFileSync(file, 'x')
    expect(await resolveRestorePath({ lastNexusPath: file })).toBeNull()
  })
})
